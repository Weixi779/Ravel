// Created by weixi on 2026/09/17.

use ravel_backend::{
    BackendCancellation, BackendError, BackendHistory, BackendRepository, BackendRevision,
};
use std::{
    io::Write,
    path::Path,
    process::{Command, Stdio},
    sync::Arc,
};
use tempfile::TempDir;

fn token() -> Arc<BackendCancellation> {
    Arc::new(BackendCancellation::new())
}
fn jj(path: &Path, args: &[&str]) -> String {
    let output = Command::new(
        std::env::var("RAVEL_TEST_JJ").unwrap_or_else(|_| "/opt/homebrew/bin/jj".into()),
    )
    .current_dir(path)
    .args(["--no-pager", "--color=never"])
    .args([
        "--config",
        "user.name='Ravel Test'",
        "--config",
        "user.email='ravel@example.com'",
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
}
fn fixture(count: usize) -> TempDir {
    let directory = tempfile::tempdir().unwrap();
    let output = Command::new("git")
        .current_dir(directory.path())
        .args(["init", "-b", "main"])
        .output()
        .unwrap();
    assert!(output.status.success());
    let mut child = Command::new("git")
        .current_dir(directory.path())
        .args(["fast-import", "--quiet"])
        .stdin(Stdio::piped())
        .spawn()
        .unwrap();
    {
        let mut input = child.stdin.take().unwrap();
        for number in 0..count {
            let description = format!("History {number} 中文 🚀\n");
            writeln!(
                input,
                "commit refs/heads/main\ncommitter Ravel <ravel@example.com> {} +0000\ndata {}\n{}",
                1_700_000_000 + number,
                description.len(),
                description
            )
            .unwrap();
        }
        writeln!(input, "done").unwrap();
    }
    assert!(child.wait().unwrap().success());
    jj(directory.path(), &["git", "init", "--colocate"]);
    // Prove the reader ignores the presentation revset but honors immutable config.
    jj(
        directory.path(),
        &["config", "set", "--repo", "revsets.log", "none()"],
    );
    jj(
        directory.path(),
        &[
            "config",
            "set",
            "--repo",
            "revset-aliases.\"immutable_heads()\"",
            "root()",
        ],
    );
    directory
}
fn open(path: &Path) -> BackendRepository {
    BackendRepository::open(path.to_str().unwrap().into()).unwrap()
}
fn ids(path: &Path) -> Vec<String> {
    jj(
        path,
        &[
            "--ignore-working-copy",
            "--at-op=@",
            "log",
            "-r",
            "all()",
            "--no-graph",
            "-T",
            "commit_id ++ '\n'",
        ],
    )
    .lines()
    .map(str::to_owned)
    .collect()
}
fn collect(query: &BackendHistory, start: u64) -> Vec<BackendRevision> {
    let mut cursor = start;
    let mut records = vec![];
    loop {
        let page = query.page(cursor, token()).unwrap();
        records.extend(page.revisions);
        if let Some(next) = page.next_cursor {
            cursor = next;
        } else {
            break;
        }
    }
    records
}

#[test]
fn pages_all_visible_history_to_root_without_snapshot_or_import() {
    let directory = fixture(451);
    let path = directory.path();
    let expected = ids(path);
    let before = jj(
        path,
        &[
            "--ignore-working-copy",
            "op",
            "log",
            "--limit",
            "1",
            "--no-graph",
            "-T",
            "id",
        ],
    );
    std::fs::write(path.join("unrecorded.txt"), "unsaved in jj").unwrap();
    let repository = open(path);
    let query = repository.history(37, token()).unwrap();
    let records = collect(&query, 0);
    let large_query = repository.history(5000, token()).unwrap();
    let large_page = large_query.page(0, token()).unwrap();
    assert_eq!(large_page.revisions.len(), expected.len());
    assert!(large_page.next_cursor.is_none());
    large_query.close();
    assert_eq!(
        records
            .iter()
            .map(|record| record.commit_id.clone())
            .collect::<Vec<_>>(),
        expected
    );
    assert!(records.len() > 450);
    let root = records.last().unwrap();
    assert!(root.commit_id.chars().all(|c| c == '0'));
    assert!(root.parent_ids.is_empty() && root.is_immutable);
    assert_eq!(
        records.iter().filter(|record| record.is_immutable).count(),
        1
    );
    assert_eq!(
        records
            .iter()
            .filter(|record| record.is_working_copy)
            .count(),
        1
    );
    assert!(
        records
            .iter()
            .find(|record| record.is_working_copy)
            .unwrap()
            .is_empty
    );
    assert_eq!(
        std::fs::read_to_string(path.join("unrecorded.txt")).unwrap(),
        "unsaved in jj"
    );
    assert_eq!(
        jj(
            path,
            &[
                "--ignore-working-copy",
                "op",
                "log",
                "--limit",
                "1",
                "--no-graph",
                "-T",
                "id"
            ]
        ),
        before
    );
    repository.close();
    assert!(matches!(query.page(0, token()), Err(BackendError::Closed)));
    assert!(matches!(
        repository.history(37, token()),
        Err(BackendError::Closed)
    ));
}

#[test]
fn query_is_pinned_and_last_page_is_replayable_after_cancellation() {
    let directory = fixture(32);
    let path = directory.path();
    let repository = open(path);
    let expected = ids(path);
    let query = repository.history(7, token()).unwrap();
    let first = query.page(0, token()).unwrap();
    assert_eq!(query.page(0, token()).unwrap(), first);
    let cancelled = token();
    cancelled.cancel();
    assert!(matches!(
        query.page(7, cancelled),
        Err(BackendError::Cancelled)
    ));
    assert!(matches!(
        query.page(3, token()),
        Err(BackendError::InvalidCursor)
    ));
    jj(path, &["new", "-m", "new operation"]);
    let mut records = first.revisions;
    records.extend(collect(&query, 7));
    assert_eq!(
        records
            .iter()
            .map(|record| record.commit_id.clone())
            .collect::<Vec<_>>(),
        expected
    );
    let fresh = repository.history(7, token()).unwrap();
    assert_ne!(query.info().operation_id, fresh.info().operation_id);
    assert_eq!(
        collect(&fresh, 0)
            .iter()
            .map(|record| record.commit_id.clone())
            .collect::<Vec<_>>(),
        ids(path)
    );
    query.close();
    fresh.close();
}

#[test]
fn concurrent_operations_are_not_reconciled_by_reader() {
    let directory = fixture(4);
    let path = directory.path();
    let operation = jj(
        path,
        &[
            "--ignore-working-copy",
            "op",
            "log",
            "--limit",
            "1",
            "--no-graph",
            "-T",
            "id",
        ],
    );
    jj(
        path,
        &["describe", "--at-op", &operation, "-m", "branch one"],
    );
    jj(
        path,
        &["describe", "--at-op", &operation, "-m", "branch two"],
    );
    let heads_path = path.join(".jj/repo/op_heads/heads");
    let heads = || {
        let mut names: Vec<_> = std::fs::read_dir(&heads_path)
            .unwrap()
            .map(|entry| entry.unwrap().file_name())
            .collect();
        names.sort();
        names
    };
    let before = heads();
    assert!(before.len() > 1);
    let repository = open(path);
    assert!(matches!(
        repository.history(1, token()),
        Err(BackendError::Read { .. })
    ));
    assert_eq!(heads(), before);
    jj(path, &["status"]);
    let query = repository.history(1, token()).unwrap();
    let records = collect(&query, 0);
    assert!(records.iter().filter(|record| record.is_divergent).count() >= 2);
    assert_eq!(
        records
            .iter()
            .map(|record| record.commit_id.clone())
            .collect::<Vec<_>>(),
        ids(path)
    );
    repository.close();
}

#[test]
fn close_interrupts_queued_reads_and_is_idempotent() {
    let directory = fixture(8);
    let repository = open(directory.path());
    let query = repository.history(1, token()).unwrap();
    let reader = query.clone();
    let request = std::thread::spawn(move || reader.page(0, token()));
    query.close();
    let result = request.join().unwrap();
    assert!(result.is_ok() || matches!(result, Err(BackendError::Closed)));
    query.close();
    assert!(matches!(query.page(0, token()), Err(BackendError::Closed)));
}
