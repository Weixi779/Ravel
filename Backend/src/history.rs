// Created by weixi on 2026/09/17.

use crate::{BackendCancellation, BackendError, load_workspace, read_error};
use futures::StreamExt;
use jj_cli::{config::load_aliases_map, ui::Ui};
use jj_lib::{
    backend::CommitId,
    fileset::FilesetAliasesMap,
    git::REMOTE_NAME_FOR_LOCAL_GIT_REPO,
    object_id::ObjectId,
    operation::Operation,
    repo::Repo,
    repo_path::RepoPathUiConverter,
    revset::{
        self, ResolvedRevsetExpression, RevsetAliasesMap, RevsetDiagnostics, RevsetExtensions,
        RevsetParseContext, RevsetWorkspaceContext, SymbolResolver,
    },
};
use std::{
    collections::{HashMap, VecDeque},
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    thread,
};

#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct BackendRevision {
    pub commit_id: String,
    pub change_id: String,
    pub parent_ids: Vec<String>,
    pub description: String,
    pub author: String,
    pub email: String,
    pub timestamp_millis: i64,
    pub bookmarks: Vec<String>,
    pub is_working_copy: bool,
    pub is_immutable: bool,
    pub has_conflict: bool,
    pub is_divergent: bool,
    pub is_empty: bool,
}

#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct BackendPage {
    pub revisions: Vec<BackendRevision>,
    pub next_cursor: Option<u64>,
}

#[derive(Clone, uniffi::Record)]
pub struct HistoryInfo {
    pub operation_id: String,
    pub workspace_path: String,
    pub backend_version: String,
}

enum Request {
    Page {
        cursor: u64,
        cancellation: Arc<BackendCancellation>,
        reply: mpsc::SyncSender<Result<BackendPage, BackendError>>,
    },
    Stop,
}

#[derive(uniffi::Object)]
pub struct BackendHistory {
    info: HistoryInfo,
    requests: mpsc::Sender<Request>,
    closed: Arc<AtomicBool>,
    worker: Mutex<Option<thread::JoinHandle<()>>>,
}

impl BackendHistory {
    pub(crate) fn signal_close(&self) {
        self.closed.store(true, Ordering::Release);
        let _ = self.requests.send(Request::Stop);
    }

    pub(crate) fn start(
        path: PathBuf,
        page_size: u32,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<Self, BackendError> {
        if !(1..=5000).contains(&page_size) {
            return Err(read_error("Page size must be between 1 and 5000"));
        }
        let (requests, receiver) = mpsc::channel();
        let (ready, startup) = mpsc::sync_channel(1);
        let closed = Arc::new(AtomicBool::new(false));
        let worker_closed = closed.clone();
        let worker = thread::Builder::new()
            .name("ravel-history".into())
            .stack_size(8 * 1024 * 1024)
            .spawn(move || {
                // jj's revset stream borrows its repository and is not Send. Keep its
                // entire lifetime on this worker, with demand-driven page requests.
                let result = pollster::block_on(run(
                    path,
                    page_size as usize,
                    cancellation,
                    receiver,
                    &ready,
                    &worker_closed,
                ));
                if let Err(error) = result {
                    let _ = ready.send(Err(error));
                }
            })
            .map_err(read_error)?;
        match startup.recv().map_err(read_error)? {
            Ok(info) => Ok(Self {
                info,
                requests,
                closed,
                worker: Mutex::new(Some(worker)),
            }),
            Err(error) => {
                let _ = worker.join();
                Err(error)
            }
        }
    }
}

#[uniffi::export]
impl BackendHistory {
    pub fn info(&self) -> HistoryInfo {
        self.info.clone()
    }

    // A cursor is valid only on this query. Retrying the last delivered cursor
    // returns the same page, including after Swift discarded a cancelled result.
    pub fn page(
        &self,
        cursor: u64,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<BackendPage, BackendError> {
        if self.closed.load(Ordering::Acquire) {
            return Err(BackendError::Closed);
        }
        cancellation.check()?;
        let (reply, result) = mpsc::sync_channel(1);
        self.requests
            .send(Request::Page {
                cursor,
                cancellation,
                reply,
            })
            .map_err(|_| BackendError::Closed)?;
        result.recv().map_err(|_| BackendError::Closed)?
    }

    pub fn close(&self) {
        self.signal_close();
        if let Some(worker) = self.worker.lock().unwrap().take() {
            let _ = worker.join();
        }
    }
}

impl Drop for BackendHistory {
    fn drop(&mut self) {
        // Drop must not block Swift's actor; explicit close provides a cleanup
        // completion boundary. The worker owns no reference back to this object.
        self.signal_close();
    }
}

async fn run(
    path: PathBuf,
    page_size: usize,
    cancellation: Arc<BackendCancellation>,
    receiver: mpsc::Receiver<Request>,
    ready: &mpsc::SyncSender<Result<HistoryInfo, BackendError>>,
    closed: &AtomicBool,
) -> Result<(), BackendError> {
    let workspace = load_workspace(&path)?;
    cancellation.check()?;
    let loader = workspace.repo_loader();
    // Do not use load_at_head(), which reconciles divergent operations. Even
    // resolve_op_for_load("@") can update redundant head pointers. Read only.
    let heads = loader
        .op_heads_store()
        .get_op_heads()
        .await
        .map_err(read_error)?;
    let [head] = heads.as_slice() else {
        return Err(read_error(
            "The repository has concurrent operations. Reconcile them with jj, then refresh.",
        ));
    };
    let data = loader
        .op_store()
        .read_operation(head)
        .await
        .map_err(read_error)?;
    let operation = Operation::new(loader.op_store().clone(), head.clone(), data);
    let repo = loader.load_at(&operation).await.map_err(read_error)?;
    let settings = workspace.settings();
    let ui = Ui::null();
    let aliases: RevsetAliasesMap =
        load_aliases_map(&ui, settings.config(), &"revset-aliases".parse().unwrap())
            .map_err(|error| read_error(error.error))?;
    let filesets: FilesetAliasesMap =
        load_aliases_map(&ui, settings.config(), &"fileset-aliases".parse().unwrap())
            .map_err(|error| read_error(error.error))?;
    let extensions = RevsetExtensions::default();
    let path_converter = RepoPathUiConverter::Fs {
        cwd: path.clone(),
        base: workspace.workspace_root().to_path_buf(),
    };
    let context = RevsetParseContext {
        aliases_map: &aliases,
        local_variables: HashMap::new(),
        user_email: settings.user_email(),
        date_pattern_context: chrono::Local::now().into(),
        default_ignored_remote: Some(REMOTE_NAME_FOR_LOCAL_GIT_REPO),
        fileset_aliases_map: &filesets,
        use_glob_by_default: settings
            .config()
            .get("ui.revsets-use-glob-by-default")
            .map_err(read_error)?,
        extensions: &extensions,
        workspace: Some(RevsetWorkspaceContext {
            path_converter: &path_converter,
            workspace_name: workspace.workspace_name(),
        }),
    };
    let immutable_expression =
        revset::parse(&mut RevsetDiagnostics::new(), "immutable()", &context)
            .map_err(read_error)?;
    let resolver = SymbolResolver::new(repo.as_ref(), extensions.symbol_resolvers());
    let immutable_expression = immutable_expression
        .resolve_user_expression(repo.as_ref(), &resolver)
        .map_err(read_error)?;
    let immutable = immutable_expression
        .evaluate(repo.as_ref())
        .map_err(read_error)?;
    let is_immutable = immutable.containing_fn();
    let all = ResolvedRevsetExpression::all()
        .evaluate(repo.as_ref())
        .map_err(read_error)?;
    let mut stream = all.stream();
    let working_copy = repo.view().get_wc_commit_id(workspace.workspace_name());
    let mut bookmarks: HashMap<CommitId, Vec<String>> = HashMap::new();
    for (name, targets) in repo.view().bookmarks() {
        let local = targets.local_target;
        let unsynced = targets
            .remote_refs
            .iter()
            .any(|(_, remote)| remote.is_tracked() && &remote.target != local);
        let label = format!(
            "{}{}",
            name.as_symbol(),
            if local.has_conflict() {
                "??"
            } else if unsynced {
                "*"
            } else {
                ""
            }
        );
        for id in local.added_ids() {
            bookmarks.entry(id.clone()).or_default().push(label.clone());
        }
        for (remote_name, remote) in targets.remote_refs {
            if remote.is_tracked() && &remote.target == local {
                continue;
            }
            let label = format!(
                "{}{}",
                name.to_remote_symbol(remote_name),
                if remote.target.has_conflict() {
                    "??"
                } else {
                    ""
                }
            );
            for id in remote.target.added_ids() {
                bookmarks.entry(id.clone()).or_default().push(label.clone());
            }
        }
    }
    cancellation.check()?;
    ready
        .send(Ok(HistoryInfo {
            operation_id: head.hex(),
            workspace_path: workspace.workspace_root().to_string_lossy().into_owned(),
            backend_version: "jj-lib 0.41.0".into(),
        }))
        .map_err(read_error)?;

    let mut offset = 0;
    let mut last_page: Option<(u64, BackendPage)> = None;
    let mut pending = VecDeque::new();
    let mut next_id = None;
    let mut exhausted = false;
    let mut stream_error: Option<BackendError> = None;
    while let Ok(request) = receiver.recv() {
        let Request::Page {
            cursor,
            cancellation,
            reply,
        } = request
        else {
            break;
        };
        let result = async {
            if closed.load(Ordering::Acquire) {
                return Err(BackendError::Closed);
            }
            cancellation.check()?;
            if let Some((previous, page)) = &last_page
                && cursor == *previous
            {
                return Ok(page.clone());
            }
            if cursor != offset || exhausted && pending.is_empty() {
                return Err(BackendError::InvalidCursor);
            }
            if let Some(error) = &stream_error {
                return Err(error.clone());
            }
            while pending.len() <= page_size && !exhausted {
                cancellation.check()?;
                if closed.load(Ordering::Acquire) {
                    return Err(BackendError::Closed);
                }
                if next_id.is_none() {
                    match stream.next().await {
                        Some(Ok(id)) => next_id = Some(id),
                        Some(Err(error)) => {
                            let error = read_error(error);
                            stream_error = Some(error.clone());
                            return Err(error);
                        }
                        None => {
                            exhausted = true;
                            break;
                        }
                    }
                }
                let id = next_id.as_ref().unwrap();
                let commit = repo.store().get_commit(id).map_err(read_error)?;
                let record = BackendRevision {
                    commit_id: id.hex(),
                    change_id: commit.change_id().reverse_hex(),
                    parent_ids: commit.parent_ids().iter().map(ObjectId::hex).collect(),
                    description: commit.description().to_owned(),
                    author: commit.author().name.clone(),
                    email: commit.author().email.clone(),
                    timestamp_millis: commit.committer().timestamp.timestamp.0,
                    bookmarks: bookmarks.get(id).cloned().unwrap_or_default(),
                    is_working_copy: working_copy == Some(id),
                    is_immutable: is_immutable(id).map_err(read_error)?,
                    has_conflict: commit.has_conflict(),
                    is_divergent: repo
                        .resolve_change_id(commit.change_id())
                        .map_err(read_error)?
                        .is_some_and(|targets| targets.is_divergent()),
                    is_empty: commit.is_empty(repo.as_ref()).await.map_err(read_error)?,
                };
                // Keep partial work across cancellation/errors, including the
                // current ID if loading its metadata failed.
                pending.push_back(record);
                next_id = None;
            }
            cancellation.check()?;
            if closed.load(Ordering::Acquire) {
                return Err(BackendError::Closed);
            }
            let revisions: Vec<_> = pending.drain(..pending.len().min(page_size)).collect();
            let next = offset + revisions.len() as u64;
            let page = BackendPage {
                revisions,
                next_cursor: if exhausted && pending.is_empty() {
                    None
                } else {
                    Some(next)
                },
            };
            last_page = Some((offset, page.clone()));
            offset = next;
            Ok(page)
        }
        .await;
        let _ = reply.send(result);
    }
    Ok(())
}
