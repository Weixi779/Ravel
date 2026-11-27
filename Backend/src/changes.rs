//
//  changes.rs
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

use crate::{BackendCancellation, BackendError, BackendFileStatus, diff, read_error};
use jj_lib::{
    backend::TreeValue,
    commit::Commit,
    matchers::FilesMatcher,
    merge::Merge,
    merged_tree::MergedTree,
    merged_tree_builder::MergedTreeBuilder,
    object_id::ObjectId,
    repo::{MutableRepo, ReadonlyRepo},
    repo_path::{RepoPath, RepoPathBuf},
    rewrite::{CommitWithSelection, restore_tree, squash_commits},
};
use std::{
    collections::{HashMap, HashSet},
    path::Path,
};
use tokio::io::AsyncReadExt;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq, uniffi::Record)]
pub struct BackendHunk {
    pub old_start: u64,
    pub old_count: u64,
    pub new_start: u64,
    pub new_count: u64,
}

#[derive(Clone, Debug, uniffi::Enum)]
pub enum BackendFileSelection {
    Whole {
        path: String,
    },
    Hunks {
        path: String,
        hunks: Vec<BackendHunk>,
    },
}

/// Construct the intermediate tree from the immutable source blobs. Re-read the original
/// native patch to reject arbitrary ranges or mismatched selections.
pub(crate) async fn select(
    workspace: &Path,
    repo: &ReadonlyRepo,
    source: &Commit,
    selection: &[BackendFileSelection],
    token: &BackendCancellation,
) -> Result<CommitWithSelection, BackendError> {
    if selection.is_empty() {
        return Err(read_error("Select at least one change."));
    }
    let op = repo.op_id().hex();
    let commit = source.id().hex();
    let files: HashMap<_, _> = diff::files(workspace, &op, &commit, token)
        .await?
        .into_iter()
        .map(|file| (file.path.clone(), file))
        .collect();
    let before = source.parent_tree(repo).await.map_err(read_error)?;
    let after = source.tree();
    let mut whole = Vec::new();
    let mut partial = Vec::new();
    let mut seen = HashSet::new();
    for item in selection {
        token.check()?;
        let path = match item {
            BackendFileSelection::Whole { path } | BackendFileSelection::Hunks { path, .. } => path,
        };
        let file = files
            .get(path)
            .filter(|f| f.status != BackendFileStatus::Unchanged)
            .ok_or_else(|| {
                read_error("File changes no longer match the selection. Review the diff.")
            })?;
        if !seen.insert(path) {
            return Err(read_error("Duplicate selected file."));
        }
        let path = RepoPathBuf::from_internal_string(path.clone()).map_err(read_error)?;
        match item {
            BackendFileSelection::Whole { .. } => {
                if file.status == BackendFileStatus::Renamed {
                    whole.push(
                        RepoPathBuf::from_internal_string(file.source_path.clone())
                            .map_err(read_error)?,
                    );
                }
                whole.push(path);
            }
            BackendFileSelection::Hunks { hunks, .. } => {
                if !matches!(
                    file.status,
                    BackendFileStatus::Modified | BackendFileStatus::Renamed
                ) || hunks.is_empty()
                {
                    return Err(read_error("Select this change as a whole file."));
                }
                let patch = diff::patch(workspace, &op, &commit, &file.path, token).await?;
                // The rename itself stays in the remaining change until the whole file is selected.
                let original_path = RepoPathBuf::from_internal_string(file.source_path.clone())
                    .map_err(read_error)?;
                let value =
                    partial_file(&original_path, &path, &before, &after, &patch, hunks).await?;
                partial.push((original_path, value));
            }
        }
    }
    let selected = restore_tree(
        &after,
        &before,
        source.conflict_label(),
        source.parents_conflict_label().await.map_err(read_error)?,
        &FilesMatcher::new(whole),
    )
    .await
    .map_err(read_error)?;
    let mut builder = MergedTreeBuilder::new(selected);
    for (path, value) in partial {
        builder.set_or_remove(path, Merge::resolved(Some(value)));
    }
    Ok(CommitWithSelection {
        commit: source.clone(),
        parent_tree: before,
        selected_tree: builder.write_tree().await.map_err(read_error)?,
    })
}

async fn partial_file(
    old_path: &RepoPath,
    path: &RepoPath,
    before: &MergedTree,
    after: &MergedTree,
    patch: &str,
    hunks: &[BackendHunk],
) -> Result<TreeValue, BackendError> {
    let before_value = before.path_value(old_path).await.map_err(read_error)?;
    let after_value = after.path_value(path).await.map_err(read_error)?;
    let (
        Some(Some(TreeValue::File {
            id: old_id,
            executable,
            copy_id,
        })),
        Some(Some(TreeValue::File { id: new_id, .. })),
    ) = (before_value.as_resolved(), after_value.as_resolved())
    else {
        return Err(read_error("Select this change as a whole file."));
    };
    let mut old = Vec::new();
    let mut new = Vec::new();
    before
        .store()
        .read_file(old_path, old_id)
        .await
        .map_err(read_error)?
        .read_to_end(&mut old)
        .await
        .map_err(read_error)?;
    after
        .store()
        .read_file(path, new_id)
        .await
        .map_err(read_error)?
        .read_to_end(&mut new)
        .await
        .map_err(read_error)?;
    let bytes = selected_bytes(&old, &new, patch, hunks)?;
    let id = before
        .store()
        .write_file(old_path, &mut bytes.as_slice())
        .await
        .map_err(read_error)?;
    Ok(TreeValue::File {
        id,
        executable: *executable,
        copy_id: copy_id.clone(),
    })
}

fn selected_bytes(
    old: &[u8],
    new: &[u8],
    patch: &str,
    hunks: &[BackendHunk],
) -> Result<Vec<u8>, BackendError> {
    fn span(token: &str, sign: char) -> Option<(u64, u64)> {
        let part = token.strip_prefix(sign)?;
        let (start, count) = part.split_once(',').unwrap_or((part, "1"));
        Some((start.parse().ok()?, count.parse().ok()?))
    }
    // Keep each original line ending and byte, including missing EOF newline and invalid UTF-8.
    fn offsets(bytes: &[u8]) -> Vec<usize> {
        let mut result = vec![0];
        result.extend(bytes.split_inclusive(|b| *b == b'\n').scan(0, |end, line| {
            *end += line.len();
            Some(*end)
        }));
        result
    }
    fn range(offsets: &[usize], start: u64, count: u64) -> Option<std::ops::Range<usize>> {
        let first: usize = if count == 0 {
            start
        } else {
            start.checked_sub(1)?
        }
        .try_into()
        .ok()?;
        Some(*offsets.get(first)?..*offsets.get(first.checked_add(count.try_into().ok()?)?)?)
    }
    let invalid = || read_error("The selected hunks changed. Review the latest diff.");
    let mut wanted: HashSet<_> = hunks.iter().copied().collect();
    if wanted.len() != hunks.len() || wanted.is_empty() {
        return Err(invalid());
    }
    let old_offsets = offsets(old);
    let new_offsets = offsets(new);
    let mut result = Vec::new();
    let mut cursor = 0;
    for header in patch.lines().filter_map(|s| s.strip_prefix("@@ ")) {
        let mut fields = header.split_ascii_whitespace();
        let (old_start, old_count) =
            span(fields.next().ok_or_else(invalid)?, '-').ok_or_else(invalid)?;
        let (new_start, new_count) =
            span(fields.next().ok_or_else(invalid)?, '+').ok_or_else(invalid)?;
        if fields.next() != Some("@@") {
            return Err(invalid());
        }
        if !wanted.remove(&BackendHunk {
            old_start,
            old_count,
            new_start,
            new_count,
        }) {
            continue;
        }
        let left = range(&old_offsets, old_start, old_count).ok_or_else(invalid)?;
        let right = range(&new_offsets, new_start, new_count).ok_or_else(invalid)?;
        result.extend_from_slice(old.get(cursor..left.start).ok_or_else(invalid)?);
        result.extend_from_slice(&new[right]);
        cursor = left.end;
    }
    if !wanted.is_empty() {
        return Err(invalid());
    }
    result.extend_from_slice(&old[cursor..]);
    Ok(result)
}

pub(crate) async fn split(
    repo: &mut MutableRepo,
    source: CommitWithSelection,
) -> Result<Commit, BackendError> {
    if source.is_empty_selection() {
        return Err(read_error("Select at least one change."));
    }
    let original = source.commit;
    let first = repo
        .rewrite_commit(&original)
        .set_tree(source.selected_tree)
        .set_description("")
        .write()
        .await
        .map_err(read_error)?;
    let mut remaining = repo.rewrite_commit(&original).detach();
    remaining.clear_rewrite_source();
    remaining.generate_new_change_id();
    remaining.set_parents(vec![first.id().clone()]);
    let second = remaining.write(repo).await.map_err(read_error)?;
    if repo
        .base_repo()
        .settings()
        .get_bool("split.legacy-bookmark-behavior")
        .map_err(read_error)?
    {
        repo.set_rewritten_commit(original.id().clone(), second.id().clone());
    }
    repo.transform_descendants(vec![original.id().clone()], async |mut rewriter| {
        rewriter.replace_parent(first.id(), [second.id()]);
        rewriter.rebase().await?.write().await?;
        Ok(())
    })
    .await
    .map_err(read_error)?;
    for (name, wc) in repo.base_repo().clone().view().wc_commit_ids() {
        if wc == original.id() {
            // Both pieces already exist in the graph. edit() would abandon a discardable
            // empty second piece if reference rewriting has just moved this workspace there.
            repo.set_wc_commit(name.clone(), second.id().clone())
                .map_err(read_error)?;
        }
    }
    repo.rebase_descendants().await.map_err(read_error)?;
    Ok(second)
}

pub(crate) async fn squash(
    repo: &mut MutableRepo,
    source: CommitWithSelection,
    destination: &Commit,
) -> Result<Commit, BackendError> {
    if source.commit.id() == destination.id() {
        return Err(read_error("Choose another destination change."));
    }
    let squashed = squash_commits(repo, &[source], destination, false)
        .await
        .map_err(read_error)?
        .ok_or_else(|| read_error("No changes to move."))?;
    let mut description = destination.description().to_owned();
    for source in squashed.abandoned_commits {
        if !source.description().is_empty() {
            if !description.is_empty() {
                if !description.ends_with('\n') {
                    description.push('\n');
                }
                if !description.ends_with("\n\n") {
                    description.push('\n');
                }
            }
            description.push_str(source.description());
        }
    }
    let rewritten = squashed
        .commit_builder
        .set_description(description)
        .write()
        .await
        .map_err(read_error)?;
    repo.rebase_descendants().await.map_err(read_error)?;
    Ok(rewritten)
}
