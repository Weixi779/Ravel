//
//  graph.rs
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

use super::*;
use futures::TryStreamExt;
use jj_lib::{
    op_store::RefTarget,
    ref_name::RefName,
    revset::ResolvedRevsetExpression,
    rewrite::{
        MoveCommitsLocation, MoveCommitsTarget, RebaseOptions, RebasedCommit, compute_move_commits,
    },
};
use std::collections::BTreeSet;

#[derive(Clone, Debug, uniffi::Enum)]
pub enum BackendGraphCommand {
    NewChild,
    Edit,
    Rebase {
        destination: BackendWriteTarget,
        descendants: bool,
    },
    CreateBookmark {
        name: String,
    },
    MoveBookmark {
        name: String,
        destination: BackendWriteTarget,
    },
    DeleteBookmark {
        name: String,
    },
}

impl BackendGraphCommand {
    pub(super) fn name(&self) -> &'static str {
        match self {
            Self::NewChild => "new",
            Self::Edit => "edit",
            Self::Rebase { .. } => "rebase",
            Self::CreateBookmark { .. }
            | Self::MoveBookmark { .. }
            | Self::DeleteBookmark { .. } => "bookmark",
        }
    }
}

async fn descendants(
    repo: &ReadonlyRepo,
    id: &CommitId,
) -> Result<BTreeSet<CommitId>, BackendError> {
    let expression = ResolvedRevsetExpression::commit(id.clone()).descendants();
    let set = expression.evaluate(repo).map_err(read_error)?;
    set.stream().try_collect().await.map_err(read_error)
}

pub(super) async fn apply(
    ctx: &WriteContext<'_>,
    repo: &Arc<ReadonlyRepo>,
    tx: &mut Transaction,
    target: BackendWriteTarget,
    command: BackendGraphCommand,
    receipt: &mut BackendWriteReceipt,
) -> Result<Option<(String, Option<Commit>)>, BackendError> {
    use BackendGraphCommand::*;
    let rewritable = matches!(command, Edit | Rebase { .. });
    let source = target::resolve(ctx, repo, &target, rewritable, receipt).await?;
    let destination = match &command {
        Rebase { destination, .. } | MoveBookmark { destination, .. } => {
            if target.operation_id != destination.operation_id {
                return Err(receipt.reject(
                    WriteDisposition::StaleTarget,
                    "Source and destination came from different history snapshots.",
                ));
            }
            Some(target::resolve(ctx, repo, destination, false, receipt).await?)
        }
        _ => None,
    };
    let (message, result) = match command {
        NewChild => {
            let child = tx
                .repo_mut()
                .check_out(ctx.name.to_owned(), &source)
                .await
                .map_err(read_error)?;
            (format!("new change on {}", source.id().hex()), child)
        }
        Edit => {
            if repo.view().get_wc_commit_id(ctx.name) != Some(source.id()) {
                tx.repo_mut()
                    .edit(ctx.name.to_owned(), &source)
                    .await
                    .map_err(read_error)?;
            }
            (format!("edit commit {}", source.id().hex()), source)
        }
        Rebase {
            descendants: include,
            ..
        } => {
            let dest = destination.unwrap();
            if source.id() == dest.id()
                || include
                    && repo
                        .index()
                        .is_ancestor(source.id(), dest.id())
                        .map_err(read_error)?
            {
                return Err(read_error(
                    "This destination would make the change its own ancestor.",
                ));
            }
            let origin = target::origin(repo, &target.operation_id).await?;
            if descendants(&origin, source.id()).await? != descendants(repo, source.id()).await? {
                return Err(receipt.reject(
                    WriteDisposition::StaleTarget,
                    "The descendants changed. Refresh and review the affected revisions.",
                ));
            }
            let ids = vec![source.id().clone()];
            let location = MoveCommitsLocation {
                new_parent_ids: vec![dest.id().clone()],
                new_child_ids: vec![],
                target: if include {
                    MoveCommitsTarget::Roots(ids)
                } else {
                    MoveCommitsTarget::Commits(ids)
                },
            };
            let plan = compute_move_commits(tx.repo(), &location)
                .await
                .map_err(read_error)?;
            let mut stats = plan
                .apply(tx.repo_mut(), &RebaseOptions::default())
                .await
                .map_err(read_error)?;
            let result = match stats.rebased_commits.remove(source.id()) {
                Some(RebasedCommit::Rewritten(commit)) => commit,
                None => source.clone(),
                Some(RebasedCommit::Abandoned { .. }) => {
                    return Err(read_error("Rebase would abandon the selected change."));
                }
            };
            (
                format!("rebase {} onto {}", source.id().hex(), dest.id().hex()),
                result,
            )
        }
        CreateBookmark { ref name }
        | MoveBookmark { ref name, .. }
        | DeleteBookmark { ref name } => {
            if name.trim().is_empty() || name.chars().any(char::is_control) {
                return Err(read_error("Enter a bookmark name."));
            }
            let name = RefName::new(name);
            let origin = target::origin(repo, &target.operation_id).await?;
            let current = repo.view().get_local_bookmark(name);
            if current != origin.view().get_local_bookmark(name) {
                return Err(receipt.reject(
                    WriteDisposition::StaleTarget,
                    "This bookmark changed. Refresh and review it again.",
                ));
            }
            let (message, result, update) = match command {
                CreateBookmark { .. } => {
                    if current.is_present() {
                        return Err(read_error("A local bookmark already has this name."));
                    }
                    (
                        format!("create bookmark {}", name.as_symbol()),
                        source.clone(),
                        RefTarget::normal(source.id().clone()),
                    )
                }
                _ => {
                    if !current.added_ids().any(|id| id == source.id()) {
                        return Err(receipt.reject(
                            WriteDisposition::StaleTarget,
                            "This bookmark no longer points to the selected change.",
                        ));
                    }
                    if let Some(dest) = destination {
                        (
                            format!("move bookmark {} to {}", name.as_symbol(), dest.id().hex()),
                            dest.clone(),
                            RefTarget::normal(dest.id().clone()),
                        )
                    } else {
                        (
                            format!("delete bookmark {}", name.as_symbol()),
                            source,
                            RefTarget::absent(),
                        )
                    }
                }
            };
            tx.repo_mut().set_local_bookmark_target(name, update);
            (message, result)
        }
    };
    tx.repo_mut()
        .rebase_descendants()
        .await
        .map_err(read_error)?;
    receipt.commit_id = Some(result.id().hex());
    receipt.change_id = Some(result.change_id().reverse_hex());
    Ok(tx.repo().has_changes().then_some((message, Some(result))))
}
