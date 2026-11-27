//
//  writer.rs
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

mod describe;
mod graph;
pub use graph::BackendGraphCommand;
mod operations;
mod organize;
pub(crate) mod preparation;
mod target;
#[cfg(test)]
mod tests;

use crate::{
    BackendCancellation, BackendError, BackendRepository, load_workspace_for, read_error, worker,
};
use futures::{FutureExt, channel::oneshot};
use jj_cli::git_util::is_colocated_git_workspace;
use jj_lib::{
    backend::CommitId,
    commit::Commit,
    git,
    lock::FileLock,
    object_id::ObjectId,
    op_heads_store::OpHeadsStore,
    ref_name::WorkspaceName,
    repo::{ReadonlyRepo, Repo},
    transaction::Transaction,
    working_copy::WorkingCopyFreshness,
};
use std::{
    collections::HashMap,
    panic::AssertUnwindSafe,
    path::Path,
    sync::{Arc, LazyLock, Mutex, Weak, mpsc},
};

pub use operations::BackendOperationHistory;

#[derive(Clone, Debug, uniffi::Record)]
pub struct BackendWriteTarget {
    pub operation_id: String,
    pub commit_id: String,
    pub change_id: String,
}

#[derive(Clone, Copy, Debug, PartialEq, uniffi::Enum)]
pub enum WriteDisposition {
    Succeeded,
    StaleTarget,
    Immutable,
    StaleWorkingCopy,
    ConcurrentOperations,
    Failed,
    Cancelled,
    CommittedWithSyncFailure,
    OutcomeUnknown,
}

#[derive(Clone, Copy, Debug, PartialEq, uniffi::Enum)]
pub enum WritePhase {
    Queued,
    Preparing,
    Validating,
    Mutating,
    Synchronizing,
}

#[derive(Clone, Copy, Debug, PartialEq, uniffi::Enum)]
pub enum SyncStatus {
    Skipped,
    Pending,
    Completed,
    Failed,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct BackendWriteReceipt {
    pub request_id: String,
    pub workspace_path: String,
    pub initial_operation_id: String,
    pub preparation_operation_id: Option<String>,
    pub mutation_operation_id: Option<String>,
    pub current_operation_id: Option<String>,
    pub commit_id: Option<String>,
    pub change_id: Option<String>,
    pub disposition: WriteDisposition,
    pub phase: WritePhase,
    pub cancellation_phase: Option<WritePhase>,
    pub working_copy: SyncStatus,
    pub git: SyncStatus,
    pub detail: Option<String>,
}

enum Command {
    Describe(BackendWriteTarget, String),
    Graph(BackendWriteTarget, BackendGraphCommand),
    Split(BackendWriteTarget, Vec<crate::BackendFileSelection>),
    Squash(BackendWriteTarget, BackendWriteTarget, Option<Vec<String>>),
    Resolve {
        target: BackendWriteTarget,
        path: String,
        resolved: Option<jj_lib::merged_tree::MergedTree>,
    },
    Snapshot(String),
    Undo {
        head: String,
        operation: String,
    },
}

impl Command {
    fn name(&self) -> &'static str {
        match self {
            Self::Describe(..) => "describe",
            Self::Graph(_, action) => action.name(),
            Self::Split(..) => "split",
            Self::Squash(..) => "squash",
            Self::Resolve { .. } => "resolve",
            Self::Snapshot(_) => "status",
            Self::Undo { .. } => "undo",
        }
    }
    fn origin(&self) -> &str {
        match self {
            Self::Describe(t, _)
            | Self::Graph(t, _)
            | Self::Split(t, _)
            | Self::Squash(t, ..)
            | Self::Resolve { target: t, .. } => &t.operation_id,
            Self::Snapshot(id) => id,
            Self::Undo { head, .. } => head,
        }
    }
}

type Job = Box<dyn FnOnce() + Send>;
pub(super) struct QueuedWrite(Mutex<Option<Job>>);

impl QueuedWrite {
    pub(super) fn run_once(&self) {
        let job = self.0.lock().unwrap().take();
        if let Some(job) = job {
            job();
        }
    }
}

type Lane = mpsc::Sender<Arc<QueuedWrite>>;
static LANES: LazyLock<Mutex<HashMap<String, Weak<Lane>>>> = LazyLock::new(Mutex::default);

fn lane(path: &str, only_if_idle: bool) -> Result<Arc<Lane>, BackendError> {
    let mut lanes = LANES.lock().unwrap();
    if let Some(lane) = lanes.get(path).and_then(Weak::upgrade) {
        if only_if_idle {
            return Err(BackendError::WriterBusy);
        }
        return Ok(lane);
    }
    lanes.retain(|_, lane| lane.strong_count() > 0);
    let (sender, receiver) = mpsc::channel::<Arc<QueuedWrite>>();
    worker::spawn("ravel-writer", move || {
        for job in receiver {
            job.run_once();
        }
        Ok(())
    })?;
    let lane = Arc::new(sender);
    lanes.insert(path.into(), Arc::downgrade(&lane));
    Ok(lane)
}

#[uniffi::export]
impl BackendRepository {
    pub async fn describe(
        &self,
        request_id: String,
        target: BackendWriteTarget,
        description: String,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<BackendWriteReceipt, BackendError> {
        self.submit(
            request_id,
            Command::Describe(target, description),
            cancellation,
            false,
        )
        .await
    }

    pub async fn graph_command(
        &self,
        request_id: String,
        source: BackendWriteTarget,
        command: BackendGraphCommand,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<BackendWriteReceipt, BackendError> {
        self.submit(
            request_id,
            Command::Graph(source, command),
            cancellation,
            false,
        )
        .await
    }

    pub async fn snapshot(
        &self,
        request_id: String,
        operation_id: String,
        only_if_idle: bool,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<BackendWriteReceipt, BackendError> {
        self.submit(
            request_id,
            Command::Snapshot(operation_id),
            cancellation,
            only_if_idle,
        )
        .await
    }

    pub async fn undo(
        &self,
        request_id: String,
        head_id: String,
        operation_id: String,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<BackendWriteReceipt, BackendError> {
        self.submit(
            request_id,
            Command::Undo {
                head: head_id,
                operation: operation_id,
            },
            cancellation,
            false,
        )
        .await
    }

    pub async fn operation_history(
        &self,
        limit: u32,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<BackendOperationHistory, BackendError> {
        let path = self.path.clone();
        self.run_read(cancellation, move |token| {
            pollster::block_on(operations::history(&path, limit, token))
        })
        .await
    }

    pub fn is_writing(&self) -> bool {
        LANES
            .lock()
            .unwrap()
            .get(&self.identity.repository_path)
            .is_some_and(|lane| lane.strong_count() > 0)
    }

    pub fn take_write_receipts(&self) -> Vec<BackendWriteReceipt> {
        std::mem::take(&mut *self.receipts.lock().unwrap())
    }
}

impl BackendRepository {
    async fn submit(
        &self,
        id: String,
        command: Command,
        token: Arc<BackendCancellation>,
        only_if_idle: bool,
    ) -> Result<BackendWriteReceipt, BackendError> {
        let (reply, result) = oneshot::channel();
        {
            let mut state = self.state.lock().unwrap();
            if state.closed {
                return Err(BackendError::Closed);
            }
            let (done, completion) = oneshot::channel();
            let lane = lane(&self.identity.repository_path, only_if_idle)?;
            let keep_lane = lane.clone();
            let path = self.path.clone();
            let receipts = self.receipts.clone();
            let cancel = token.clone();
            let job = Arc::new(QueuedWrite(Mutex::new(Some(Box::new(move || {
                let _lane = keep_lane;
                let mut receipt = BackendWriteReceipt::new(id, &path, &command);
                let outcome = std::panic::catch_unwind(AssertUnwindSafe(|| {
                    pollster::block_on(execute(&path, command, &cancel, &mut receipt))
                }));
                match outcome {
                    Ok(Ok(())) => (),
                    Ok(Err(error)) => receipt.fail(error),
                    Err(_) => {
                        receipt.disposition = WriteDisposition::OutcomeUnknown;
                        receipt.detail = Some(
                            "The writer stopped unexpectedly. Inspect local operation history."
                                .into(),
                        );
                    }
                }
                if cancel.check().is_err() && receipt.mutation_operation_id.is_some() {
                    receipt.cancellation_phase = Some(WritePhase::Synchronizing);
                }
                receipts.lock().unwrap().push(receipt.clone());
                let _ = reply.send(receipt);
                let _ = done.send(());
            })))));
            lane.send(job.clone())
                .map_err(|_| read_error("The repository writer stopped"))?;
            state
                .register(token, completion.map(|_| ()).boxed().shared())
                .queued_write = Some(Arc::downgrade(&job));
        }
        result
            .await
            .map_err(|_| read_error("The repository writer stopped before returning a receipt"))
    }
}

impl BackendWriteReceipt {
    fn enter(&mut self, phase: WritePhase, _token: &BackendCancellation) {
        self.phase = phase;
        #[cfg(test)]
        if let Some(observer) = &_token.write_checkpoint {
            observer(phase);
        }
    }

    fn new(id: String, path: &Path, command: &Command) -> Self {
        Self {
            request_id: id,
            workspace_path: path.to_string_lossy().into_owned(),
            initial_operation_id: command.origin().into(),
            current_operation_id: None,
            preparation_operation_id: None,
            mutation_operation_id: None,
            commit_id: None,
            change_id: None,
            disposition: WriteDisposition::Succeeded,
            phase: WritePhase::Queued,
            cancellation_phase: None,
            working_copy: SyncStatus::Skipped,
            git: SyncStatus::Skipped,
            detail: None,
        }
    }

    fn fail(&mut self, error: BackendError) {
        if matches!(error, BackendError::Cancelled) {
            self.cancellation_phase = Some(self.phase);
            self.disposition = WriteDisposition::Cancelled;
        } else if self.mutation_operation_id.is_some() {
            self.disposition = WriteDisposition::CommittedWithSyncFailure;
        } else if self.disposition == WriteDisposition::Succeeded {
            self.disposition = WriteDisposition::Failed;
        }
        self.detail = Some(error.to_string());
    }

    fn reject(&mut self, kind: WriteDisposition, message: &str) -> BackendError {
        self.disposition = kind;
        read_error(message)
    }
}

fn working_commit(repo: &ReadonlyRepo, name: &WorkspaceName) -> Result<Commit, BackendError> {
    let id = repo
        .view()
        .get_wc_commit_id(name)
        .ok_or_else(|| read_error("Workspace was removed"))?;
    repo.store().get_commit(id).map_err(read_error)
}

// The caller holds jj's operation-head lock. Publishing directly under that lock
// keeps validation and the head update together, including across different workspaces.
async fn publish(
    tx: Transaction,
    description: &str,
    heads: &dyn OpHeadsStore,
    receipt: &mut BackendWriteReceipt,
) -> Result<Arc<ReadonlyRepo>, BackendError> {
    let unpublished = tx.write(description).await.map_err(read_error)?;
    let op = unpublished.operation();
    heads
        .update_op_heads(op.parent_ids(), op.id())
        .await
        .map_err(|err| {
            receipt.disposition = WriteDisposition::OutcomeUnknown;
            receipt.current_operation_id = None;
            read_error(format!(
                "Inspect operation {} in local operation history: {err}",
                op.id().hex()
            ))
        })?;
    let repo = unpublished.leave_unpublished();
    receipt.current_operation_id = Some(repo.op_id().hex());
    Ok(repo)
}

async fn execute(
    path: &Path,
    mut command: Command,
    token: &BackendCancellation,
    receipt: &mut BackendWriteReceipt,
) -> Result<(), BackendError> {
    token.check()?;
    receipt.enter(WritePhase::Preparing, token);
    let mut workspace = load_workspace_for(path, command.name())?;
    let loader = workspace.repo_loader().clone();
    let name = workspace.workspace_name().to_owned();
    let settings = workspace.settings().clone();
    let heads = loader.op_heads_store().clone();
    let before = operations::head(&loader, receipt).await?;
    let colocated = is_colocated_git_workspace(&workspace, &before);
    let context = WriteContext {
        path,
        name: &name,
        settings: &settings,
        heads: heads.as_ref(),
        colocated,
    };
    // External tools may stay open while the user works in another jj client. Revalidate
    // both the working copy and the full source after the tool exits and preparation runs.
    if let Command::Resolve {
        target,
        path: file,
        resolved,
    } = &mut command
    {
        let source = target::resolve(&context, &before, target, true, receipt).await?;
        *resolved = Some(crate::conflict::edit(path, &settings, &source, file).await?);
        token.check()?;
    }
    let _git_lock = if colocated {
        Some(
            FileLock::lock(workspace.repo_path().join("git_import_export.lock"))
                .map_err(read_error)?,
        )
    } else {
        None
    };
    let mut locked = workspace
        .start_working_copy_mutation()
        .await
        .map_err(read_error)?;
    let _head_lock = heads.lock().await.map_err(read_error)?;
    let mut repo = operations::head(&loader, receipt).await?;
    let old = working_commit(&repo, &name)?;
    if !matches!(
        WorkingCopyFreshness::check_stale(locked.locked_wc(), &old, &repo)
            .await
            .map_err(read_error)?,
        WorkingCopyFreshness::Fresh
    ) {
        return Err(receipt.reject(
            WriteDisposition::StaleWorkingCopy,
            "Run jj workspace update-stale, then refresh and review.",
        ));
    }
    token.check()?;
    // Preparation may publish independently of the requested command.
    repo = match preparation::prepare(&context, &repo, locked.locked_wc(), token, receipt).await {
        Ok(repo) => repo,
        Err(error) => {
            if receipt.preparation_operation_id.is_some()
                && receipt.working_copy == SyncStatus::Pending
                && let Some(id) = receipt
                    .current_operation_id
                    .as_deref()
                    .and_then(jj_lib::op_store::OperationId::try_from_hex)
            {
                receipt.working_copy = match locked.finish(id).await {
                    Ok(()) => SyncStatus::Completed,
                    Err(_) => SyncStatus::Failed,
                };
            }
            return Err(error);
        }
    };
    let prepared_wc = working_commit(&repo, &name)?;
    let mutation = mutate(&context, &repo, command, token, receipt).await;
    // Finish already committed effects even if the caller or repository closed.
    let result = match mutation {
        Ok(Some(committed)) => {
            repo = committed;
            receipt.enter(WritePhase::Synchronizing, token);
            receipt.working_copy = SyncStatus::Pending;
            if colocated {
                receipt.git = SyncStatus::Pending;
            }
            let new_wc = working_commit(&repo, &name)?;
            let checkout = if prepared_wc.tree().tree_ids_and_labels()
                != new_wc.tree().tree_ids_and_labels()
            {
                locked
                    .locked_wc()
                    .check_out(&new_wc)
                    .await
                    .map(|_| ())
                    .map_err(read_error)
            } else {
                Ok(())
            };
            checkout.inspect_err(|_| {
                receipt.working_copy = SyncStatus::Failed;
            })?;
            if colocated {
                match preparation::export(&repo, &name, &new_wc, heads.as_ref(), receipt).await {
                    Ok(exported) => {
                        repo = exported;
                        receipt.git = SyncStatus::Completed;
                        Ok(())
                    }
                    Err(error) => {
                        receipt.git = SyncStatus::Failed;
                        Err(error)
                    }
                }
            } else {
                Ok(())
            }
        }
        Ok(None) => Ok(()),
        Err(error) => Err(error),
    };
    let final_id = receipt
        .current_operation_id
        .as_deref()
        .and_then(jj_lib::op_store::OperationId::try_from_hex)
        .unwrap_or_else(|| repo.op_id().clone());
    locked.finish(final_id).await.map_err(|error| {
        receipt.working_copy = SyncStatus::Failed;
        read_error(error)
    })?;
    if receipt.working_copy == SyncStatus::Pending || receipt.preparation_operation_id.is_some() {
        receipt.working_copy = SyncStatus::Completed;
    }
    result
}

struct WriteContext<'a> {
    path: &'a Path,
    name: &'a WorkspaceName,
    settings: &'a jj_lib::settings::UserSettings,
    heads: &'a dyn OpHeadsStore,
    colocated: bool,
}

async fn mutate(
    ctx: &WriteContext<'_>,
    repo: &Arc<ReadonlyRepo>,
    command: Command,
    token: &BackendCancellation,
    receipt: &mut BackendWriteReceipt,
) -> Result<Option<Arc<ReadonlyRepo>>, BackendError> {
    token.check()?;
    receipt.enter(WritePhase::Validating, token);
    token.check()?;
    let mut tx = repo.start_transaction();
    tx.set_workspace_name(ctx.name);
    let change = match command {
        Command::Graph(source, action) => {
            graph::apply(ctx, repo, &mut tx, source, action, receipt).await?
        }
        Command::Snapshot(_) => {
            let wc = working_commit(repo, ctx.name)?;
            receipt.commit_id = Some(wc.id().hex());
            receipt.change_id = Some(wc.change_id().reverse_hex());
            None
        }
        Command::Describe(target, message) => {
            describe::rewrite(ctx, repo, &mut tx, target, message, receipt).await?
        }
        Command::Split(target, selection) => {
            let source = target::resolve(ctx, repo, &target, true, receipt).await?;
            receipt.phase = WritePhase::Mutating;
            let picked = crate::changes::select(ctx.path, repo, &source, &selection, token).await?;
            let second = crate::changes::split(tx.repo_mut(), picked).await?;
            Some((format!("split commit {}", source.id().hex()), Some(second)))
        }
        Command::Squash(target, destination, paths) => {
            let source = target::resolve(ctx, repo, &target, true, receipt).await?;
            let dest = target::resolve(ctx, repo, &destination, true, receipt).await?;
            receipt.phase = WritePhase::Mutating;
            let picked = if let Some(paths) = paths {
                let files = paths
                    .into_iter()
                    .map(|path| crate::BackendFileSelection::Whole { path })
                    .collect::<Vec<_>>();
                crate::changes::select(ctx.path, repo, &source, &files, token).await?
            } else {
                jj_lib::rewrite::CommitWithSelection {
                    parent_tree: source
                        .parent_tree(repo.as_ref())
                        .await
                        .map_err(read_error)?,
                    selected_tree: source.tree(),
                    commit: source.clone(),
                }
            };
            let dest = crate::changes::squash(tx.repo_mut(), picked, &dest).await?;
            Some((format!("squash commit {}", source.id().hex()), Some(dest)))
        }
        Command::Resolve {
            target,
            path,
            resolved,
        } => {
            let source = target::resolve(ctx, repo, &target, true, receipt).await?;
            let tree = resolved.ok_or_else(|| read_error("No merge tool result."))?;
            receipt.phase = WritePhase::Mutating;
            let new = tx
                .repo_mut()
                .rewrite_commit(&source)
                .set_tree(tree)
                .write()
                .await
                .map_err(read_error)?;
            tx.repo_mut()
                .rebase_descendants()
                .await
                .map_err(read_error)?;
            Some((format!("resolve conflict in {path}"), Some(new)))
        }
        Command::Undo { head, operation } => Some((
            operations::restore(repo, &mut tx, ctx.name, &head, &operation, receipt).await?,
            None,
        )),
    };
    let Some((description, new)) = change else {
        return Ok(None);
    };
    receipt.enter(WritePhase::Mutating, token);
    token.check()?;
    let committed = publish(tx, &description, ctx.heads, receipt).await?;
    receipt.mutation_operation_id = Some(committed.op_id().hex());
    if let Some(new) = new {
        receipt.commit_id = Some(new.id().hex());
        receipt.change_id = Some(new.change_id().reverse_hex());
    }
    Ok(Some(committed))
}
