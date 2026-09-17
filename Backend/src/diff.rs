// Created by weixi on 2026/09/17.

use crate::{BackendCancellation, BackendError, load_workspace_for, read_error};
use futures::StreamExt;
use jj_cli::{
    diff_util::{
        DiffEntryStatus, DiffStatOptions, DiffStats, UnifiedDiffOptions, diff_status,
        get_copy_records, show_git_diff,
    },
    formatter::PlainTextFormatter,
};
use jj_lib::{
    backend::{CommitId, TreeValue},
    copies::CopyRecords,
    matchers::{EverythingMatcher, FilesMatcher, Matcher},
    merge::{Diff, MergedTreeValue},
    merged_tree::MergedTree,
    op_store::OperationId,
    operation::Operation,
    repo::{ReadonlyRepo, Repo},
    repo_path::RepoPath,
    rewrite::merge_commit_trees,
    workspace::Workspace,
};
use std::{
    io::{self, Write},
    path::Path,
    sync::Arc,
};

#[derive(Clone, Debug, PartialEq, uniffi::Enum)]
pub enum BackendFileStatus {
    Modified,
    Added,
    Removed,
    Copied,
    Renamed,
    Unchanged,
}

#[derive(Clone, Debug, PartialEq, uniffi::Enum)]
pub enum BackendFileKind {
    File,
    Symlink,
    Directory,
    Submodule,
    Conflict,
}

#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct BackendFileMetadata {
    pub kind: BackendFileKind,
    pub executable: Option<bool>,
    pub conflict_sides: u32,
}

impl BackendFileMetadata {
    fn from_value(value: &MergedTreeValue) -> Option<Self> {
        let (kind, executable) = match value.as_resolved() {
            Some(None) => return None,
            Some(Some(TreeValue::File { executable, .. })) => {
                (BackendFileKind::File, Some(*executable))
            }
            Some(Some(TreeValue::Symlink(_))) => (BackendFileKind::Symlink, None),
            Some(Some(TreeValue::Tree(_))) => (BackendFileKind::Directory, None),
            Some(Some(TreeValue::GitSubmodule(_))) => (BackendFileKind::Submodule, None),
            None => (BackendFileKind::Conflict, None),
        };
        Some(Self {
            kind,
            executable,
            conflict_sides: if value.is_resolved() {
                0
            } else {
                value.num_sides() as u32
            },
        })
    }
}

#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct BackendChangedFile {
    pub path: String,
    pub source_path: String,
    pub status: BackendFileStatus,
    pub before: Option<BackendFileMetadata>,
    pub after: Option<BackendFileMetadata>,
}

#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct BackendFileStatistics {
    pub path: String,
    /// None for binary changes; zero is reserved for an actual zero-line change.
    pub lines_added: Option<u64>,
    pub lines_removed: Option<u64>,
    pub bytes_delta: i64,
}

#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct BackendDiffStatistics {
    pub files: Vec<BackendFileStatistics>,
    pub lines_added: u64,
    pub lines_removed: u64,
    pub binary_files: u64,
}

struct DiffView {
    workspace: Workspace,
    repo: Arc<ReadonlyRepo>,
    before: MergedTree,
    after: MergedTree,
    copies: CopyRecords,
}

impl DiffView {
    async fn open(
        path: &Path,
        operation_id: &str,
        commit_id: &str,
        matcher: &dyn Matcher,
        cancellation: &BackendCancellation,
    ) -> Result<Self, BackendError> {
        cancellation.check()?;
        let workspace = load_workspace_for(path, "diff")?;
        let loader = workspace.repo_loader();
        let operation_id = OperationId::try_from_hex(operation_id)
            .filter(|_| !operation_id.is_empty())
            .ok_or_else(|| read_error("Invalid operation ID"))?;
        let data = loader
            .op_store()
            .read_operation(&operation_id)
            .await
            .map_err(read_error)?;
        let operation = Operation::new(loader.op_store().clone(), operation_id, data);
        let repo = loader.load_at(&operation).await.map_err(read_error)?;
        cancellation.check()?;
        let commit_id = CommitId::try_from_hex(commit_id)
            .filter(|_| !commit_id.is_empty())
            .ok_or_else(|| read_error("Invalid commit ID"))?;
        let commit = repo.store().get_commit(&commit_id).map_err(read_error)?;
        let parents = commit.parents().await.map_err(read_error)?;
        // This is the same single-revision comparison as jj diff --revisions:
        // merge all parents first, so a clean merge has no synthetic changes.
        let before = merge_commit_trees(repo.as_ref(), &parents)
            .await
            .map_err(read_error)?;
        let after = commit.tree();
        cancellation.check()?;
        let mut copies = CopyRecords::default();
        for parent in &parents {
            copies.add_records(
                get_copy_records(repo.store(), parent.id(), commit.id(), matcher)
                    .await
                    .map_err(read_error)?,
            );
            cancellation.check()?;
        }
        Ok(Self {
            workspace,
            repo,
            before,
            after,
            copies,
        })
    }
}

pub(crate) async fn files(
    path: &Path,
    operation_id: &str,
    commit_id: &str,
    cancellation: &BackendCancellation,
) -> Result<Vec<BackendChangedFile>, BackendError> {
    let matcher = EverythingMatcher;
    let view = DiffView::open(path, operation_id, commit_id, &matcher, cancellation).await?;
    let mut stream = view
        .before
        .diff_stream_with_copies(&view.after, &matcher, &view.copies);
    let mut files = Vec::new();
    while let Some(entry) = stream.next().await {
        cancellation.check()?;
        let values = entry.values.map_err(read_error)?;
        let status = match diff_status(&entry.path, &values) {
            DiffEntryStatus::Modified => BackendFileStatus::Modified,
            DiffEntryStatus::Added => BackendFileStatus::Added,
            DiffEntryStatus::Removed => BackendFileStatus::Removed,
            DiffEntryStatus::Copied => BackendFileStatus::Copied,
            DiffEntryStatus::Renamed => BackendFileStatus::Renamed,
        };
        files.push(BackendChangedFile {
            path: entry.path.target().as_internal_file_string().to_owned(),
            source_path: entry.path.source().as_internal_file_string().to_owned(),
            status,
            before: BackendFileMetadata::from_value(&values.before),
            after: BackendFileMetadata::from_value(&values.after),
        });
    }
    // An unresolved merge can have an empty delta against its merged parents.
    // Keep those conflicts discoverable without inventing a content modification.
    for (path, value) in view.after.conflicts() {
        cancellation.check()?;
        let path_string = path.as_internal_file_string();
        if files.iter().any(|file| file.path == path_string) {
            continue;
        }
        let before = view.before.path_value(&path).await.map_err(read_error)?;
        files.push(BackendChangedFile {
            path: path_string.to_owned(),
            source_path: path_string.to_owned(),
            status: BackendFileStatus::Unchanged,
            before: BackendFileMetadata::from_value(&before),
            after: BackendFileMetadata::from_value(&value.map_err(read_error)?),
        });
    }
    files.sort_by(|left, right| left.path.cmp(&right.path));
    cancellation.check()?;
    Ok(files)
}

pub(crate) async fn statistics(
    path: &Path,
    operation_id: &str,
    commit_id: &str,
    cancellation: &BackendCancellation,
) -> Result<BackendDiffStatistics, BackendError> {
    let matcher = EverythingMatcher;
    let view = DiffView::open(path, operation_id, commit_id, &matcher, cancellation).await?;
    let marker_style = view
        .workspace
        .settings()
        .get("ui.conflict-marker-style")
        .map_err(read_error)?;
    let mut stream = view
        .before
        .diff_stream_with_copies(&view.after, &matcher, &view.copies);
    let mut result = BackendDiffStatistics {
        files: Vec::new(),
        lines_added: 0,
        lines_removed: 0,
        binary_files: 0,
    };
    while let Some(entry) = stream.next().await {
        cancellation.check()?;
        // One file at a time keeps cancellation responsive between expensive file diffs.
        let stats = DiffStats::calculate(
            view.repo.store(),
            futures::stream::iter([entry]).boxed(),
            &DiffStatOptions::default(),
            marker_style,
        )
        .await
        .map_err(read_error)?;
        cancellation.check()?;
        for entry in stats.entries() {
            result.lines_added += entry.added_removed.map_or(0, |(added, _)| added as u64);
            result.lines_removed += entry.added_removed.map_or(0, |(_, removed)| removed as u64);
            result.binary_files += u64::from(entry.added_removed.is_none());
            result.files.push(BackendFileStatistics {
                path: entry.path.target().as_internal_file_string().to_owned(),
                lines_added: entry.added_removed.map(|(added, _)| added as u64),
                lines_removed: entry.added_removed.map(|(_, removed)| removed as u64),
                bytes_delta: entry.bytes_delta as i64,
            });
        }
    }
    Ok(result)
}

pub(crate) async fn patch(
    path: &Path,
    operation_id: &str,
    commit_id: &str,
    file_path: &str,
    cancellation: &BackendCancellation,
) -> Result<String, BackendError> {
    let file = RepoPath::from_internal_string(file_path).map_err(read_error)?;
    let matcher = FilesMatcher::new([file]);
    let view = DiffView::open(path, operation_id, commit_id, &matcher, cancellation).await?;
    let mut options =
        UnifiedDiffOptions::from_settings(view.workspace.settings()).map_err(read_error)?;
    options.context = 3;
    let marker_style = view
        .workspace
        .settings()
        .get("ui.conflict-marker-style")
        .map_err(read_error)?;
    let mut output = PatchOutput {
        bytes: Vec::new(),
        lines: 0,
        too_large: false,
        cancellation,
    };
    let result = show_git_diff(
        &mut PlainTextFormatter::new(&mut output),
        view.repo.store(),
        view.before
            .diff_stream_with_copies(&view.after, &matcher, &view.copies),
        Diff::new(view.before.labels(), view.after.labels()),
        &options,
        marker_style,
    )
    .await;
    cancellation.check()?;
    if output.too_large {
        return Err(BackendError::DiffTooLarge);
    }
    result.map_err(read_error)?;
    Ok(String::from_utf8_lossy(&output.bytes).into_owned())
}

struct PatchOutput<'a> {
    bytes: Vec<u8>,
    lines: usize,
    too_large: bool,
    cancellation: &'a BackendCancellation,
}

impl Write for PatchOutput<'_> {
    fn write(&mut self, data: &[u8]) -> io::Result<usize> {
        self.cancellation.check().map_err(io::Error::other)?;
        let lines = self.lines + data.iter().filter(|&&byte| byte == b'\n').count();
        if self.bytes.len().saturating_add(data.len()) >= 2 * 1024 * 1024 || lines > 20_000 {
            self.too_large = true;
            return Err(io::Error::other("Diff preview limit exceeded"));
        }
        self.bytes.extend_from_slice(data);
        self.lines = lines;
        Ok(data.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn patch_output_stops_before_byte_and_line_limits_and_observes_cancellation() {
        let cancellation = BackendCancellation::new();
        for contents in [vec![b'x'; 2 * 1024 * 1024], vec![b'\n'; 20_001]] {
            let mut output = PatchOutput {
                bytes: Vec::new(),
                lines: 0,
                too_large: false,
                cancellation: &cancellation,
            };
            assert!(output.write_all(&contents).is_err());
            assert!(output.too_large);
            assert!(output.bytes.is_empty());
        }
        let mut output = PatchOutput {
            bytes: Vec::new(),
            lines: 0,
            too_large: false,
            cancellation: &cancellation,
        };
        output.write_all(b"diff\n").unwrap();
        cancellation.cancel();
        assert!(output.write_all(b"late contents").is_err());
        assert_eq!(output.bytes, b"diff\n");
    }
}
