// Created by weixi on 2026/09/17.

use crate::{BackendCancellation, BackendError, load_workspace, read_error, worker};
use futures::{StreamExt, channel::oneshot};
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
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
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
        reply: oneshot::Sender<Result<BackendPage, BackendError>>,
    },
    Stop,
}

#[derive(uniffi::Object)]
pub struct BackendHistory {
    info: HistoryInfo,
    worker: Arc<HistoryWorker>,
}

pub(crate) struct HistoryWorker {
    requests: mpsc::Sender<Request>,
    closed: Arc<AtomicBool>,
    pub(crate) finished: worker::Completion,
}

impl HistoryWorker {
    pub(crate) fn signal_close(&self) {
        self.closed.store(true, Ordering::Release);
        let _ = self.requests.send(Request::Stop);
    }

    async fn close(&self) {
        self.signal_close();
        self.finished.clone().await;
    }
}

impl Drop for HistoryWorker {
    fn drop(&mut self) {
        // Destruction only signals; explicit close awaits native resource cleanup.
        self.signal_close();
    }
}

pub(crate) struct PendingHistory {
    pub(crate) worker: Arc<HistoryWorker>,
    startup: oneshot::Receiver<Result<HistoryInfo, BackendError>>,
}

impl PendingHistory {
    pub(crate) async fn ready(self) -> Result<Arc<BackendHistory>, BackendError> {
        match self.startup.await.unwrap_or_else(|_| {
            Err(read_error(
                "The history worker stopped during initialization",
            ))
        }) {
            Ok(info) => Ok(Arc::new(BackendHistory {
                info,
                worker: self.worker,
            })),
            Err(error) => {
                self.worker.close().await;
                Err(error)
            }
        }
    }
}

impl BackendHistory {
    pub(crate) fn start(
        path: PathBuf,
        page_size: u32,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<PendingHistory, BackendError> {
        if !(1..=5000).contains(&page_size) {
            return Err(read_error("Page size must be between 1 and 5000"));
        }
        let (requests, receiver) = mpsc::channel();
        let (ready, startup) = oneshot::channel();
        let closed = Arc::new(AtomicBool::new(false));
        let worker_closed = closed.clone();
        let worker = worker::spawn("ravel-history", move || {
            let mut ready = Some(ready);
            // jj's revset stream borrows its repository and is not Send. Keep its
            // entire lifetime on this worker, with demand-driven page requests.
            let result = pollster::block_on(run(
                path,
                page_size as usize,
                cancellation,
                receiver,
                &mut ready,
                &worker_closed,
            ));
            if let Err(error) = result
                && let Some(ready) = ready.take()
            {
                let _ = ready.send(Err(error));
            }
            Ok(())
        })?;
        Ok(PendingHistory {
            worker: Arc::new(HistoryWorker {
                requests,
                closed,
                finished: worker.finished,
            }),
            startup,
        })
    }
}

#[uniffi::export]
impl BackendHistory {
    pub fn info(&self) -> HistoryInfo {
        self.info.clone()
    }

    // A cursor is valid only on this query. Retrying the last delivered cursor
    // returns the same page, including after Swift discarded a cancelled result.
    pub async fn page(
        &self,
        cursor: u64,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<BackendPage, BackendError> {
        if self.worker.closed.load(Ordering::Acquire) {
            return Err(BackendError::Closed);
        }
        cancellation.check()?;
        let (reply, result) = oneshot::channel();
        self.worker
            .requests
            .send(Request::Page {
                cursor,
                cancellation,
                reply,
            })
            .map_err(|_| BackendError::Closed)?;
        result.await.map_err(|_| BackendError::Closed)?
    }

    pub async fn close(&self) {
        self.worker.close().await;
    }
}

async fn run(
    path: PathBuf,
    page_size: usize,
    cancellation: Arc<BackendCancellation>,
    receiver: mpsc::Receiver<Request>,
    ready: &mut Option<oneshot::Sender<Result<HistoryInfo, BackendError>>>,
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
    if closed.load(Ordering::Acquire) {
        return Err(BackendError::Closed);
    }
    ready
        .take()
        .unwrap()
        .send(Ok(HistoryInfo {
            operation_id: head.hex(),
            workspace_path: workspace.workspace_root().to_string_lossy().into_owned(),
            backend_version: "jj-lib 0.41.0".into(),
        }))
        .map_err(|_| BackendError::Closed)?;

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

#[cfg(test)]
mod tests {
    use super::*;
    use futures::FutureExt;

    // Exercise the exported page/close futures with a controlled native producer.
    fn query() -> (BackendHistory, mpsc::Receiver<Request>, oneshot::Sender<()>) {
        let (requests, receiver) = mpsc::channel();
        let (release, released) = oneshot::channel();
        let worker = Arc::new(HistoryWorker {
            requests,
            closed: Arc::new(AtomicBool::new(false)),
            finished: released.map(|_| ()).boxed().shared(),
        });
        (
            BackendHistory {
                info: HistoryInfo {
                    operation_id: String::new(),
                    workspace_path: String::new(),
                    backend_version: String::new(),
                },
                worker,
            },
            receiver,
            release,
        )
    }

    #[test]
    fn page_suspends_until_reply_and_close_suspends_until_cleanup() {
        let (query, requests, cleanup) = query();
        let token = Arc::new(BackendCancellation::new());
        let mut page = Box::pin(query.page(0, token.clone()));
        assert!(page.as_mut().now_or_never().is_none());
        let Request::Page {
            cursor,
            cancellation,
            reply,
        } = requests.try_recv().unwrap()
        else {
            panic!()
        };
        assert_eq!(cursor, 0);
        assert!(Arc::ptr_eq(&token, &cancellation));
        let expected = BackendPage {
            revisions: vec![],
            next_cursor: Some(7),
        };
        reply.send(Ok(expected.clone())).unwrap();
        assert_eq!(pollster::block_on(page).unwrap(), expected);
        let mut first = Box::pin(query.close());
        let mut second = Box::pin(query.close());
        assert!(first.as_mut().now_or_never().is_none());
        assert!(second.as_mut().now_or_never().is_none());
        assert!(query.worker.closed.load(Ordering::Acquire));
        assert!(matches!(
            pollster::block_on(query.page(7, token)),
            Err(BackendError::Closed)
        ));
        cleanup.send(()).unwrap();
        pollster::block_on(async {
            futures::join!(first, second);
        });
    }

    #[test]
    fn startup_failure_waits_for_cleanup_before_returning() {
        let (query, _requests, cleanup) = query();
        let (ready, startup) = oneshot::channel();
        let mut starting = Box::pin(
            PendingHistory {
                worker: query.worker.clone(),
                startup,
            }
            .ready(),
        );
        assert!(starting.as_mut().now_or_never().is_none());
        ready.send(Err(BackendError::Cancelled)).ok().unwrap();
        assert!(starting.as_mut().now_or_never().is_none());
        assert!(query.worker.closed.load(Ordering::Acquire));
        cleanup.send(()).unwrap();
        assert!(matches!(
            pollster::block_on(starting),
            Err(BackendError::Cancelled)
        ));
    }

    #[test]
    fn cancelled_page_is_not_enqueued_and_dropped_reply_does_not_hang() {
        let (query, requests, _cleanup) = query();
        let token = Arc::new(BackendCancellation::new());
        token.cancel();
        assert!(matches!(
            pollster::block_on(query.page(0, token)),
            Err(BackendError::Cancelled)
        ));
        assert!(matches!(
            requests.try_recv(),
            Err(mpsc::TryRecvError::Empty)
        ));
        let mut page = Box::pin(query.page(0, Arc::new(BackendCancellation::new())));
        assert!(page.as_mut().now_or_never().is_none());
        drop(requests.try_recv().unwrap());
        assert!(matches!(
            pollster::block_on(page),
            Err(BackendError::Closed)
        ));
    }
}
