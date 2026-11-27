//
//  operations.rs
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

use super::*;
use futures::StreamExt;
use jj_lib::{op_store::OperationId, op_walk, operation::Operation, repo::RepoLoader};

#[derive(Clone, Debug, uniffi::Record)]
pub struct BackendOperation {
    pub id: String,
    pub description: String,
    pub timestamp_millis: i64,
    pub workspace_name: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct BackendOperationHistory {
    pub head_id: String,
    pub entries: Vec<BackendOperation>,
    pub undo_target: Option<BackendOperation>,
}

fn entry(op: &Operation) -> BackendOperation {
    let data = op.metadata();
    BackendOperation {
        id: op.id().hex(),
        description: data.description.clone(),
        timestamp_millis: data.time.end.timestamp.0,
        workspace_name: data.workspace_name.as_ref().map(|w| w.as_str().into()),
    }
}

pub(super) async fn head(
    loader: &RepoLoader,
    receipt: &mut BackendWriteReceipt,
) -> Result<Arc<ReadonlyRepo>, BackendError> {
    let ids = loader
        .op_heads_store()
        .get_op_heads()
        .await
        .map_err(read_error)?;
    let [id] = ids.as_slice() else {
        receipt.current_operation_id = None;
        return Err(receipt.reject(
            WriteDisposition::ConcurrentOperations,
            "Concurrent operation heads. Run jj status in this workspace to reconcile the heads, then refresh and review.",
        ));
    };
    receipt.current_operation_id = Some(id.hex());
    let op = loader.load_operation(id).await.map_err(read_error)?;
    loader.load_at(&op).await.map_err(read_error)
}

const UNDO_PREFIX: &str = "undo: restore to operation ";

async fn restored_op(repo: &ReadonlyRepo, op: Operation) -> Result<Operation, BackendError> {
    if let Some(value) = op.metadata().description.strip_prefix(UNDO_PREFIX) {
        let id =
            OperationId::try_from_hex(value).ok_or_else(|| read_error("Invalid undo operation"))?;
        return repo.loader().load_operation(&id).await.map_err(read_error);
    }
    Ok(op)
}

async fn user_operation(repo: &ReadonlyRepo, mut op: Operation) -> Result<Operation, BackendError> {
    if let [parent] = op.parent_ids()
        && op.metadata().attributes.get("ravel.git-sync") == Some(&parent.hex())
    {
        op = repo
            .loader()
            .load_operation(parent)
            .await
            .map_err(read_error)?;
    }
    Ok(op)
}

async fn undo_target(repo: &ReadonlyRepo) -> Result<Operation, BackendError> {
    let current = user_operation(repo, repo.operation().clone()).await?;
    user_operation(repo, restored_op(repo, current).await?).await
}

pub(super) async fn history(
    path: &Path,
    limit: u32,
    token: &BackendCancellation,
) -> Result<BackendOperationHistory, BackendError> {
    if !(1..=1000).contains(&limit) {
        return Err(read_error("Invalid operation history limit"));
    }
    let workspace = load_workspace_for(path, "op log")?;
    let loader = workspace.repo_loader();
    let ids = loader
        .op_heads_store()
        .get_op_heads()
        .await
        .map_err(read_error)?;
    let [id] = ids.as_slice() else {
        return Err(read_error(
            "Concurrent operation heads. Run jj status in this workspace to reconcile the heads, then refresh and review.",
        ));
    };
    let op = loader.load_operation(id).await.map_err(read_error)?;
    let repo = loader.load_at(&op).await.map_err(read_error)?;
    let target = undo_target(&repo).await?;
    let mut entries = Vec::new();
    let stream = op_walk::walk_ancestors(&[op]).take(limit as usize);
    futures::pin_mut!(stream);
    while let Some(op) = stream.next().await {
        token.check()?;
        entries.push(entry(&op.map_err(read_error)?));
    }
    Ok(BackendOperationHistory {
        head_id: id.hex(),
        entries,
        undo_target: (target.parent_ids().len() == 1).then(|| entry(&target)),
    })
}

pub(super) async fn restore(
    repo: &ReadonlyRepo,
    tx: &mut Transaction,
    workspace: &WorkspaceName,
    head: &str,
    expected: &str,
    receipt: &mut BackendWriteReceipt,
) -> Result<String, BackendError> {
    let target = undo_target(repo).await?;
    if repo.op_id().hex() != head || target.id().hex() != expected {
        return Err(receipt.reject(
            WriteDisposition::StaleTarget,
            "Local history changed. Review the operation that Undo would now restore.",
        ));
    }
    let [parent] = target.parent_ids() else {
        return Err(read_error("Cannot undo a root or merge operation"));
    };
    let op = repo
        .loader()
        .load_operation(parent)
        .await
        .map_err(read_error)?;
    let op = user_operation(
        repo,
        restored_op(repo, user_operation(repo, op).await?).await?,
    )
    .await?;
    let mut view = op.view().await.map_err(read_error)?.store_view().clone();
    if !view.wc_commit_ids.contains_key(workspace) {
        return Err(read_error(
            "Undo would remove the open workspace. Review this operation in another workspace.",
        ));
    }
    // Keep knowledge of actual Git refs and HEAD until local export reconciles them.
    view.git_refs = repo.view().store_view().git_refs.clone();
    view.git_head = repo.view().git_head().clone();
    tx.repo_mut().set_view(view);
    Ok(format!("{UNDO_PREFIX}{}", op.id().hex()))
}
