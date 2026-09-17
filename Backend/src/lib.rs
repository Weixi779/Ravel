// Created by weixi on 2026/09/17.

mod diff;
mod history;

pub use diff::{BackendChangedFile, BackendFileStatus};
pub use history::{BackendHistory, BackendPage, BackendRevision, HistoryInfo};
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
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{
    Arc, Condvar, Mutex, Weak,
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
    queries: Vec<Weak<BackendHistory>>,
    next_read_id: u64,
    reads: HashMap<u64, Arc<BackendCancellation>>,
}

#[derive(uniffi::Object)]
pub struct BackendRepository {
    path: PathBuf,
    identity: RepositoryIdentity,
    state: Mutex<RepositoryState>,
    reads_finished: Condvar,
}

#[uniffi::export]
impl BackendRepository {
    #[uniffi::constructor]
    pub fn open(path: String) -> Result<Self, BackendError> {
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
            reads_finished: Condvar::new(),
        })
    }

    pub fn identity(&self) -> RepositoryIdentity {
        self.identity.clone()
    }

    pub fn diff(
        &self,
        operation_id: String,
        commit_id: String,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<Vec<BackendChangedFile>, BackendError> {
        self.run_read(cancellation, |token| {
            pollster::block_on(diff::files(&self.path, &operation_id, &commit_id, token))
        })
    }

    pub fn file_diff(
        &self,
        operation_id: String,
        commit_id: String,
        file_path: String,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<String, BackendError> {
        self.run_read(cancellation, |token| {
            pollster::block_on(diff::patch(
                &self.path,
                &operation_id,
                &commit_id,
                &file_path,
                token,
            ))
        })
    }

    pub fn history(
        &self,
        page_size: u32,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<Arc<BackendHistory>, BackendError> {
        cancellation.check()?;
        if self.state.lock().unwrap().closed {
            return Err(BackendError::Closed);
        }
        let query = Arc::new(BackendHistory::start(
            self.path.clone(),
            page_size,
            cancellation,
        )?);
        let mut state = self.state.lock().unwrap();
        if state.closed {
            drop(state);
            query.close();
            return Err(BackendError::Closed);
        }
        state.queries.retain(|query| query.strong_count() > 0);
        state.queries.push(Arc::downgrade(&query));
        Ok(query)
    }

    // Waits for workers to release their read views. Call off the UI actor.
    pub fn close(&self) {
        let (queries, reads) = {
            let mut state = self.state.lock().unwrap();
            state.closed = true;
            (
                std::mem::take(&mut state.queries),
                state.reads.values().cloned().collect::<Vec<_>>(),
            )
        };
        for token in reads {
            token.cancel();
        }
        for query in queries.into_iter().filter_map(|query| query.upgrade()) {
            query.close();
        }
        let state = self.state.lock().unwrap();
        drop(
            self.reads_finished
                .wait_while(state, |state| !state.reads.is_empty())
                .unwrap(),
        );
    }
}

impl BackendRepository {
    fn run_read<T: Send>(
        &self,
        cancellation: Arc<BackendCancellation>,
        read: impl FnOnce(&BackendCancellation) -> Result<T, BackendError> + Send,
    ) -> Result<T, BackendError> {
        cancellation.check()?;
        let id = {
            let mut state = self.state.lock().unwrap();
            if state.closed {
                return Err(BackendError::Closed);
            }
            let id = state.next_read_id;
            state.next_read_id += 1;
            state.reads.insert(id, cancellation.clone());
            id
        };
        let _registration = ReadRegistration {
            repository: self,
            id,
        };
        // Keep jj's non-Send objects and recursive tree work on a native stack.
        // Joining also makes completion mean all resources have been released.
        std::thread::scope(|scope| {
            std::thread::Builder::new()
                .name("ravel-diff".into())
                .stack_size(8 * 1024 * 1024)
                .spawn_scoped(scope, || {
                    cancellation.check()?;
                    let result = read(&cancellation)?;
                    cancellation.check()?;
                    Ok(result)
                })
                .map_err(read_error)?
                .join()
                .map_err(|_| read_error("The native diff worker failed"))?
        })
    }
}

struct ReadRegistration<'a> {
    repository: &'a BackendRepository,
    id: u64,
}

impl Drop for ReadRegistration<'_> {
    fn drop(&mut self) {
        self.repository.state.lock().unwrap().reads.remove(&self.id);
        self.repository.reads_finished.notify_all();
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
        for query in self
            .state
            .get_mut()
            .unwrap()
            .queries
            .iter()
            .filter_map(Weak::upgrade)
        {
            query.signal_close();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;

    #[test]
    fn close_cancels_native_reads_and_waits_for_resource_release() {
        let repository = Arc::new(BackendRepository {
            path: PathBuf::new(),
            identity: RepositoryIdentity {
                workspace_path: String::new(),
                repository_path: String::new(),
                workspace_name: String::new(),
            },
            state: Mutex::default(),
            reads_finished: Condvar::new(),
        });
        let cancellation = Arc::new(BackendCancellation::new());
        let (started, ready) = mpsc::channel();
        let (cancelled, observed) = mpsc::channel();
        let (release, released) = mpsc::channel();
        let reader = repository.clone();
        let worker = std::thread::spawn(move || {
            reader.run_read(cancellation, move |token| {
                started.send(()).unwrap();
                while token.check().is_ok() {
                    std::thread::yield_now();
                }
                cancelled.send(()).unwrap();
                released.recv().unwrap();
                Ok(())
            })
        });
        ready.recv().unwrap();
        let closer = repository.clone();
        let (closed, completed) = mpsc::channel();
        let close = std::thread::spawn(move || {
            closer.close();
            closed.send(()).unwrap();
        });
        observed.recv().unwrap();
        assert!(matches!(
            completed.try_recv(),
            Err(mpsc::TryRecvError::Empty)
        ));
        release.send(()).unwrap();
        assert!(matches!(
            worker.join().unwrap(),
            Err(BackendError::Cancelled)
        ));
        completed.recv().unwrap();
        close.join().unwrap();
        assert!(matches!(
            repository.diff(
                String::new(),
                String::new(),
                Arc::new(BackendCancellation::new())
            ),
            Err(BackendError::Closed)
        ));
    }
}
