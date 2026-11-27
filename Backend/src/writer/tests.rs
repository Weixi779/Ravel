//
//  tests.rs
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

use super::*;
use pollster::block_on;
use std::{fs, process::Command as Cli, time::Duration};
use tempfile::TempDir;

fn jj(path: &Path, args: &[&str]) -> String {
    let result =
        Cli::new(std::env::var("RAVEL_TEST_JJ").unwrap_or_else(|_| "/opt/homebrew/bin/jj".into()))
            .current_dir(path)
            .args([
                "--config",
                "user.name='Writer Test'",
                "--config",
                "user.email='writer@example.org'",
            ])
            .args(args)
            .output()
            .unwrap();
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    String::from_utf8(result.stdout).unwrap().trim().into()
}

fn fixture() -> TempDir {
    let dir = tempfile::tempdir().unwrap();
    jj(dir.path(), &["git", "init", "--colocate"]);
    jj(dir.path(), &["describe", "-m", "one"]);
    jj(dir.path(), &["new", "-m", "two"]);
    dir
}

fn target(path: &Path, revision: &str) -> BackendWriteTarget {
    let id = jj(
        path,
        &[
            "--ignore-working-copy",
            "log",
            "-r",
            revision,
            "--no-graph",
            "-T",
            "commit_id ++ ' ' ++ change_id",
        ],
    );
    let (commit, change) = id.split_once(' ').unwrap();
    let op = jj(
        path,
        &[
            "--ignore-working-copy",
            "op",
            "log",
            "--no-graph",
            "-n",
            "1",
            "-T",
            "id",
        ],
    );
    BackendWriteTarget {
        operation_id: op,
        commit_id: commit.into(),
        change_id: change.into(),
    }
}

fn open(path: &Path) -> BackendRepository {
    block_on(BackendRepository::open(path.to_string_lossy().into_owned())).unwrap()
}

#[test]
fn cancellation_preserves_committed_effects_at_each_boundary() {
    for phase in [
        WritePhase::Queued,
        WritePhase::Preparing,
        WritePhase::Validating,
        WritePhase::Mutating,
        WritePhase::Synchronizing,
    ] {
        let dir = fixture();
        let path = dir.path();
        let repo = open(path);
        let selected = target(path, "@-");
        fs::write(path.join("new-file"), "disk edit").unwrap();
        let token = Arc::new_cyclic(|weak: &Weak<BackendCancellation>| {
            let weak = weak.clone();
            BackendCancellation {
                write_checkpoint: Some(Box::new(move |current| {
                    if current == phase {
                        weak.upgrade().unwrap().cancel();
                    }
                })),
                ..Default::default()
            }
        });
        if phase == WritePhase::Queued {
            token.cancel();
        }
        let receipt =
            block_on(repo.describe("cancel".into(), selected, "edited\n".into(), token)).unwrap();
        assert_eq!(receipt.cancellation_phase, Some(phase), "{receipt:?}");
        let prepared = matches!(
            phase,
            WritePhase::Validating | WritePhase::Mutating | WritePhase::Synchronizing
        );
        assert_eq!(receipt.preparation_operation_id.is_some(), prepared);
        let committed = phase == WritePhase::Synchronizing;
        assert_eq!(receipt.mutation_operation_id.is_some(), committed);
        assert_eq!(
            receipt.disposition,
            if committed {
                WriteDisposition::Succeeded
            } else {
                WriteDisposition::Cancelled
            }
        );
        assert_eq!(
            jj(
                path,
                &[
                    "--ignore-working-copy",
                    "log",
                    "--no-graph",
                    "-r",
                    "@-",
                    "-T",
                    "description"
                ]
            ),
            if committed { "edited" } else { "one" }
        );
        assert_eq!(
            fs::read_to_string(path.join("new-file")).unwrap(),
            "disk edit"
        );
    }
}

#[test]
fn working_copy_sync_failure_retains_published_mutation() {
    let dir = fixture();
    let path = dir.path();
    let repo = open(path);
    let selected = target(path, "@");
    let state = path.join(".jj/working_copy/checkout");
    let token = Arc::new(BackendCancellation {
        write_checkpoint: Some(Box::new(move |phase| {
            if phase == WritePhase::Synchronizing {
                fs::rename(&state, state.with_extension("original")).unwrap();
                fs::create_dir(&state).unwrap();
            }
        })),
        ..Default::default()
    });
    let receipt =
        block_on(repo.describe("wc failure".into(), selected, "published\n".into(), token))
            .unwrap();
    assert_eq!(
        receipt.disposition,
        WriteDisposition::CommittedWithSyncFailure,
        "{receipt:?}"
    );
    assert_eq!(receipt.working_copy, SyncStatus::Failed);
    assert!(receipt.mutation_operation_id.is_some());
    // Restore only the broken checkout-state file so the independent CLI can open
    // the fixture. Reading with --ignore-working-copy leaves the repo head alone.
    let state = path.join(".jj/working_copy/checkout");
    fs::remove_dir(&state).unwrap();
    fs::rename(state.with_extension("original"), state).unwrap();
    assert_eq!(
        jj(
            path,
            &[
                "--ignore-working-copy",
                "log",
                "--no-graph",
                "-r",
                "@",
                "-T",
                "description"
            ]
        ),
        "published"
    );
}

#[test]
fn shared_lane_close_releases_queued_workspace_and_waits_for_active_cleanup() {
    let dir = fixture();
    let parent = tempfile::tempdir().unwrap();
    let other_path = parent.path().join("other");
    jj(
        dir.path(),
        &["workspace", "add", other_path.to_str().unwrap()],
    );
    let first = open(dir.path());
    let second = open(&other_path);
    let selected = target(dir.path(), "@-");
    let other = target(&other_path, "@");
    let (started, waiting) = mpsc::channel();
    let (release, released) = mpsc::channel();
    let released = Mutex::new(released);
    let token = Arc::new(BackendCancellation {
        write_checkpoint: Some(Box::new(move |phase| {
            if phase == WritePhase::Synchronizing {
                started.send(()).unwrap();
                released
                    .lock()
                    .unwrap()
                    .recv_timeout(Duration::from_secs(10))
                    .unwrap();
            }
        })),
        ..Default::default()
    });
    let mut first_write =
        Box::pin(first.describe("active".into(), selected, "saved\n".into(), token));
    assert!(first_write.as_mut().now_or_never().is_none());
    waiting.recv_timeout(Duration::from_secs(5)).unwrap();
    assert!(second.is_writing());
    assert!(matches!(
        block_on(second.snapshot(
            "focus".into(),
            other.operation_id.clone(),
            true,
            Arc::default()
        )),
        Err(BackendError::WriterBusy)
    ));
    let mut pending = Box::pin(second.describe(
        "queued".into(),
        other,
        "must not run\n".into(),
        Arc::default(),
    ));
    assert!(pending.as_mut().now_or_never().is_none());
    drop(pending);
    block_on(second.close());
    let rejected = second.take_write_receipts();
    assert_eq!(rejected.len(), 1);
    assert_eq!(rejected[0].cancellation_phase, Some(WritePhase::Queued));
    assert!(rejected[0].preparation_operation_id.is_none());
    assert!(matches!(
        block_on(second.snapshot("closed".into(), String::new(), false, Arc::default())),
        Err(BackendError::Closed)
    ));
    drop(first_write);
    let mut closing = Box::pin(first.close());
    assert!(closing.as_mut().now_or_never().is_none());
    release.send(()).unwrap();
    block_on(closing);
    let saved = first.take_write_receipts();
    assert_eq!(saved.len(), 1);
    assert_eq!(saved[0].disposition, WriteDisposition::Succeeded);
    assert_eq!(saved[0].cancellation_phase, Some(WritePhase::Synchronizing));
    assert!(saved[0].mutation_operation_id.is_some());
}

#[test]
fn concurrent_terminal_heads_are_reported_without_merging_or_writing() {
    let dir = fixture();
    let path = dir.path();
    let repo = open(path);
    let selected = target(path, "@");
    for message in ["left", "right"] {
        jj(
            path,
            &["describe", "--at-op", &selected.operation_id, "-m", message],
        );
    }
    let receipt =
        block_on(repo.describe("concurrent".into(), selected, "lost".into(), Arc::default()))
            .unwrap();
    assert_eq!(receipt.disposition, WriteDisposition::ConcurrentOperations);
    assert!(receipt.preparation_operation_id.is_none());
    assert!(receipt.mutation_operation_id.is_none());
    assert!(receipt.current_operation_id.is_none());
    assert_eq!(
        fs::read_dir(path.join(".jj/repo/op_heads/heads"))
            .unwrap()
            .count(),
        2
    );
}

#[test]
fn snapshots_external_git_head_and_respects_git_excludes() {
    let dir = fixture();
    let path = dir.path();
    let repo = open(path);
    let selected = target(path, "@");
    let git = |args: &[&str]| {
        let output = Cli::new("git")
            .current_dir(path)
            .args([
                "-c",
                "user.name=External",
                "-c",
                "user.email=external@example.org",
            ])
            .args(args)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8(output.stdout).unwrap().trim().to_owned()
    };
    fs::write(path.join("external.txt"), "from Git").unwrap();
    git(&["add", "external.txt"]);
    git(&["commit", "-m", "external commit"]);
    let head = git(&["rev-parse", "HEAD"]);
    fs::write(path.join(".git/info/exclude"), "ignored.txt\n").unwrap();
    fs::write(path.join("ignored.txt"), "ignored").unwrap();
    fs::write(path.join("tracked.txt"), "from editor").unwrap();
    let receipt = block_on(repo.snapshot(
        "explicit".into(),
        selected.operation_id,
        false,
        Arc::default(),
    ))
    .unwrap();
    assert_eq!(
        receipt.disposition,
        WriteDisposition::Succeeded,
        "{receipt:?}"
    );
    assert!(receipt.preparation_operation_id.is_some());
    assert_eq!(
        jj(
            path,
            &[
                "--ignore-working-copy",
                "log",
                "-r",
                "@-",
                "--no-graph",
                "-T",
                "commit_id"
            ]
        ),
        head
    );
    let files = jj(path, &["--ignore-working-copy", "file", "list", "-r", "@"]);
    assert!(files.contains("tracked.txt"));
    assert!(!files.contains("ignored.txt"));
}

#[test]
fn immutable_and_failed_precommit_requests_leave_descriptions_intact() {
    let dir = fixture();
    let path = dir.path();
    let repo = open(path);
    let immutable = target(path, "root()");
    let result = block_on(repo.describe(
        "immutable".into(),
        immutable,
        "root changed".into(),
        Arc::default(),
    ))
    .unwrap();
    assert_eq!(result.disposition, WriteDisposition::Immutable);
    let mut invalid = target(path, "@");
    invalid.commit_id.truncate(8);
    let result =
        block_on(repo.describe("invalid".into(), invalid, "changed".into(), Arc::default()))
            .unwrap();
    assert_eq!(result.disposition, WriteDisposition::Failed);
    assert!(result.mutation_operation_id.is_none());
    assert_eq!(
        jj(
            path,
            &[
                "--ignore-working-copy",
                "log",
                "--no-graph",
                "-r",
                "@",
                "-T",
                "description"
            ]
        ),
        "two"
    );
}

#[test]
fn stale_workspace_blocks_writes_before_snapshotting_local_files() {
    let dir = fixture();
    let path = dir.path();
    let selected = target(path, "@");
    let repo = open(path);
    let sibling_parent = tempfile::tempdir().unwrap();
    let sibling = sibling_parent.path().join("sibling");
    jj(
        path,
        &["workspace", "add", "-r", "@", sibling.to_str().unwrap()],
    );
    // Change the tree of the original workspace from another workspace.
    fs::write(sibling.join("from-sibling"), "new base").unwrap();
    jj(&sibling, &["squash", "-m", "updated by sibling"]);
    fs::write(path.join("local"), "keep my edit").unwrap();
    let receipt = block_on(repo.describe(
        "stale workspace".into(),
        selected,
        "no write".into(),
        Arc::default(),
    ))
    .unwrap();
    assert_eq!(
        receipt.disposition,
        WriteDisposition::StaleWorkingCopy,
        "{receipt:?}"
    );
    assert!(receipt.preparation_operation_id.is_none());
    assert!(receipt.mutation_operation_id.is_none());
    assert_eq!(
        fs::read_to_string(path.join("local")).unwrap(),
        "keep my edit"
    );
}
