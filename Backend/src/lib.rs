//
//  lib.rs
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

mod changes;
mod conflict;
pub use changes::{BackendFileSelection, BackendHunk};
mod diff;
mod history;
mod window_status;
mod worker;
mod writer;
pub use writer::{
    BackendGraphCommand, BackendOperationHistory, BackendWriteReceipt, BackendWriteTarget,
    SyncStatus, WriteDisposition, WritePhase,
};

pub use diff::{
    BackendChangedFile, BackendDiffStatistics, BackendFileKind, BackendFileMetadata,
    BackendFileStatistics, BackendFileStatus,
};
use futures::FutureExt;
pub use history::{
    BackendBookmarkLocation, BackendHistory, BackendPage, BackendRevision, HistoryInfo,
};
use jj_cli::{
    config::{self, ConfigEnv},
    ui::Ui,
};
use jj_lib::{
    repo::StoreFactories,
    settings::UserSettings,
    workspace::{
        DefaultWorkspaceLoaderFactory, Workspace, WorkspaceLoaderFactory,
        default_working_copy_factories,
    },
};
use std::path::{Path, PathBuf};
use std::sync::{
    Arc, Mutex, Weak,
    atomic::{AtomicBool, Ordering},
};

uniffi::setup_scaffolding!();

#[derive(Debug, Clone, thiserror::Error, uniffi::Error)]
pub enum BackendError {
    #[error("{message}")]
    Read { message: String },
    #[error("The request was cancelled")]
    Cancelled,
    #[error("The repository or history query is closed")]
    Closed,
    #[error("The repository writer is busy")]
    WriterBusy,
    #[error("The cursor does not belong to the current page of this history query")]
    InvalidCursor,
    #[error("The diff exceeds the preview limit")]
    DiffTooLarge,
}

fn read_error(error: impl std::fmt::Display) -> BackendError {
    BackendError::Read {
        message: error.to_string(),
    }
}

#[derive(Default, uniffi::Object)]
pub struct BackendCancellation {
    cancelled: AtomicBool,
    #[cfg(test)]
    write_checkpoint: Option<Box<dyn Fn(WritePhase) + Send + Sync>>,
}

#[uniffi::export]
impl BackendCancellation {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self::default()
    }
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }
}

impl BackendCancellation {
    fn check(&self) -> Result<(), BackendError> {
        if self.cancelled.load(Ordering::Acquire) {
            Err(BackendError::Cancelled)
        } else {
            Ok(())
        }
    }
}

#[derive(Clone, uniffi::Record)]
pub struct RepositoryIdentity {
    pub workspace_path: String,
    pub repository_path: String,
    pub workspace_name: String,
}

#[derive(Default)]
struct RepositoryState {
    closed: bool,
    queries: Vec<Weak<history::HistoryWorker>>,
    workers: Vec<ActiveWorker>,
}

#[derive(Clone)]
struct ActiveWorker {
    cancellation: Arc<BackendCancellation>,
    finished: worker::Completion,
    queued_write: Option<Weak<writer::QueuedWrite>>,
}

impl RepositoryState {
    fn register(
        &mut self,
        cancellation: Arc<BackendCancellation>,
        finished: worker::Completion,
    ) -> &mut ActiveWorker {
        self.workers
            .retain(|worker| worker.finished.clone().now_or_never().is_none());
        self.workers.push(ActiveWorker {
            cancellation,
            finished,
            queued_write: None,
        });
        self.workers.last_mut().unwrap()
    }
}

#[derive(uniffi::Object)]
pub struct BackendRepository {
    path: PathBuf,
    identity: RepositoryIdentity,
    state: Mutex<RepositoryState>,
    receipts: Arc<Mutex<Vec<BackendWriteReceipt>>>,
}

#[uniffi::export]
impl BackendRepository {
    #[uniffi::constructor]
    pub async fn open(path: String) -> Result<Self, BackendError> {
        worker::spawn("ravel-open", move || Self::open_on_worker(path))?
            .result()
            .await
    }

    pub fn identity(&self) -> RepositoryIdentity {
        self.identity.clone()
    }

    pub async fn diff(
        &self,
        operation_id: String,
        commit_id: String,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<Vec<BackendChangedFile>, BackendError> {
        let path = self.path.clone();
        self.run_read(cancellation, move |token| {
            pollster::block_on(diff::files(&path, &operation_id, &commit_id, token))
        })
        .await
    }

    pub async fn file_diff(
        &self,
        operation_id: String,
        commit_id: String,
        file_path: String,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<String, BackendError> {
        let path = self.path.clone();
        self.run_read(cancellation, move |token| {
            pollster::block_on(diff::patch(
                &path,
                &operation_id,
                &commit_id,
                &file_path,
                token,
            ))
        })
        .await
    }

    pub async fn diff_statistics(
        &self,
        operation_id: String,
        commit_id: String,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<BackendDiffStatistics, BackendError> {
        let path = self.path.clone();
        self.run_read(cancellation, move |token| {
            pollster::block_on(diff::statistics(&path, &operation_id, &commit_id, token))
        })
        .await
    }

    pub async fn history(
        &self,
        page_size: u32,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<Arc<BackendHistory>, BackendError> {
        cancellation.check()?;
        let pending = {
            let mut state = self.state.lock().unwrap();
            if state.closed {
                return Err(BackendError::Closed);
            }
            let pending =
                BackendHistory::start(self.path.clone(), page_size, cancellation.clone())?;
            // Register before awaiting startup, so close also stops initializing queries.
            state.queries.retain(|query| query.strong_count() > 0);
            state.queries.push(Arc::downgrade(&pending.worker));
            state.register(cancellation.clone(), pending.worker.finished.clone());
            pending
        };
        let query = pending.ready().await?;
        let closed = self.state.lock().unwrap().closed;
        if closed || cancellation.check().is_err() {
            query.close().await;
            return Err(if closed {
                BackendError::Closed
            } else {
                BackendError::Cancelled
            });
        }
        Ok(query)
    }

    /// Await cleanup of every admitted worker, including initialization and dropped callers.
    pub async fn close(&self) {
        let workers = self.signal_close();
        futures::future::join_all(workers.into_iter().map(|worker| worker.finished)).await;
    }
}

impl BackendRepository {
    fn open_on_worker(path: String) -> Result<Self, BackendError> {
        let workspace = load_workspace(Path::new(&path))?;
        let path = workspace.workspace_root().to_path_buf();
        let identity = RepositoryIdentity {
            workspace_path: path.to_string_lossy().into_owned(),
            repository_path: workspace
                .repo_path()
                .canonicalize()
                .map_err(read_error)?
                .to_string_lossy()
                .into_owned(),
            workspace_name: workspace.workspace_name().as_str().to_owned(),
        };
        Ok(Self {
            path,
            identity,
            state: Mutex::default(),
            receipts: Arc::default(),
        })
    }

    fn signal_close(&self) -> Vec<ActiveWorker> {
        let (queries, workers) = {
            let mut state = self.state.lock().unwrap();
            state.closed = true;
            (
                state
                    .queries
                    .iter()
                    .filter_map(Weak::upgrade)
                    .collect::<Vec<_>>(),
                state.workers.clone(),
            )
        };
        for worker in &workers {
            worker.cancellation.cancel();
            if let Some(job) = worker.queued_write.as_ref().and_then(Weak::upgrade) {
                job.run_once();
            }
        }
        for query in queries {
            query.signal_close();
        }
        workers
    }

    async fn run_read<T: Send + 'static>(
        &self,
        cancellation: Arc<BackendCancellation>,
        read: impl FnOnce(&BackendCancellation) -> Result<T, BackendError> + Send + 'static,
    ) -> Result<T, BackendError> {
        cancellation.check()?;
        let worker = {
            let mut state = self.state.lock().unwrap();
            if state.closed {
                return Err(BackendError::Closed);
            }
            let token = cancellation.clone();
            let worker = worker::spawn("ravel-diff", move || {
                token.check()?;
                let result = read(&token)?;
                token.check()?;
                Ok(result)
            })?;
            state.register(cancellation, worker.finished.clone());
            worker
        };
        worker.result().await
    }
}

fn load_workspace(path: &Path) -> Result<Workspace, BackendError> {
    load_workspace_for(path, "log")
}

fn load_workspace_for(path: &Path, command: &str) -> Result<Workspace, BackendError> {
    let loader = DefaultWorkspaceLoaderFactory
        .create(path)
        .map_err(read_error)?;
    let ui = Ui::null();
    let mut raw = config::config_from_environment(config::default_config_layers());
    let mut env = ConfigEnv::from_environment();
    env.set_command_name(command.to_owned());
    env.reload_user_config(&mut raw).map_err(read_error)?;
    env.reset_repo_path(loader.repo_path());
    env.reload_repo_config(&ui, &mut raw)
        .map_err(|error| read_error(error.error))?;
    env.reset_workspace_path(loader.workspace_root());
    env.reload_workspace_config(&ui, &mut raw)
        .map_err(|error| read_error(error.error))?;
    let settings = UserSettings::from_config(env.resolve_config(&raw).map_err(read_error)?)
        .map_err(read_error)?;
    loader
        .load(
            &settings,
            &StoreFactories::default(),
            &default_working_copy_factories(),
        )
        .map_err(read_error)
}

impl Drop for BackendRepository {
    fn drop(&mut self) {
        self.signal_close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::FutureExt;
    use std::sync::mpsc;
    use std::time::Duration;

    fn repository() -> BackendRepository {
        BackendRepository {
            path: PathBuf::new(),
            identity: RepositoryIdentity {
                workspace_path: String::new(),
                repository_path: String::new(),
                workspace_name: String::new(),
            },
            state: Mutex::default(),
            receipts: Arc::default(),
        }
    }

    #[test]
    fn close_cancels_reads_and_all_callers_await_cleanup_even_after_read_is_dropped() {
        struct Resource(Arc<AtomicBool>);
        impl Drop for Resource {
            fn drop(&mut self) {
                self.0.store(true, Ordering::Release);
            }
        }
        let repository = repository();
        let cancellation = Arc::new(BackendCancellation::new());
        let cleaned_up = Arc::new(AtomicBool::new(false));
        let resource = Resource(cleaned_up.clone());
        let (started, ready) = mpsc::channel();
        let (release, released) = mpsc::channel();
        let mut read = Box::pin(repository.run_read(cancellation.clone(), move |token| {
            let _resource = resource;
            started.send(()).unwrap();
            released.recv().unwrap();
            token.check()
        }));
        assert!(read.as_mut().now_or_never().is_none());
        ready.recv_timeout(Duration::from_secs(5)).unwrap();
        let mut first_close = Box::pin(repository.close());
        let mut second_close = Box::pin(repository.close());
        assert!(first_close.as_mut().now_or_never().is_none());
        assert!(second_close.as_mut().now_or_never().is_none());
        assert!(matches!(cancellation.check(), Err(BackendError::Cancelled)));
        assert!(!cleaned_up.load(Ordering::Acquire));
        // Dropping the async caller must not remove a still-running worker from close.
        drop(read);
        assert!(first_close.as_mut().now_or_never().is_none());
        release.send(()).unwrap();
        pollster::block_on(async {
            futures::join!(first_close, second_close);
        });
        assert!(cleaned_up.load(Ordering::Acquire));
        assert!(matches!(
            pollster::block_on(
                repository.run_read(Arc::new(BackendCancellation::new()), |_| Ok(()))
            ),
            Err(BackendError::Closed)
        ));
    }

    #[test]
    fn cancelled_read_is_rejected_before_work_starts() {
        let repository = repository();
        let cancellation = Arc::new(BackendCancellation::new());
        cancellation.cancel();
        let result = pollster::block_on(repository.run_read::<()>(cancellation, |_| {
            panic!("a pre-cancelled read must not run")
        }));
        assert!(matches!(result, Err(BackendError::Cancelled)));
        assert!(repository.state.lock().unwrap().workers.is_empty());
    }

    #[test]
    fn cancellation_during_work_discards_result_after_cleanup() {
        let repository = repository();
        let cancellation = Arc::new(BackendCancellation::new());
        let (release, released) = mpsc::channel();
        let mut read = Box::pin(repository.run_read(cancellation.clone(), move |_| {
            released.recv().unwrap();
            Ok(42)
        }));
        assert!(read.as_mut().now_or_never().is_none());
        cancellation.cancel();
        release.send(()).unwrap();
        assert!(matches!(
            pollster::block_on(read),
            Err(BackendError::Cancelled)
        ));
        pollster::block_on(repository.close());
    }
}
