// Created by weixi on 2026/09/17.

mod history;

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
    #[error("The cursor does not belong to the current page of this history query")]
    InvalidCursor,
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
}

#[derive(uniffi::Object)]
pub struct BackendRepository {
    path: PathBuf,
    identity: RepositoryIdentity,
    state: Mutex<RepositoryState>,
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
        })
    }

    pub fn identity(&self) -> RepositoryIdentity {
        self.identity.clone()
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
        let queries = {
            let mut state = self.state.lock().unwrap();
            state.closed = true;
            std::mem::take(&mut state.queries)
        };
        for query in queries.into_iter().filter_map(|query| query.upgrade()) {
            query.close();
        }
    }
}

fn load_workspace(path: &Path) -> Result<Workspace, BackendError> {
    let loader = DefaultWorkspaceLoaderFactory
        .create(path)
        .map_err(read_error)?;
    let ui = Ui::null();
    let mut raw = config::config_from_environment(config::default_config_layers());
    let mut env = ConfigEnv::from_environment();
    env.set_command_name("log".to_owned());
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
