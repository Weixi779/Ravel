//
//  preparation.rs
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

use super::*;
use jj_cli::{config::load_aliases_map, git_util::load_git_import_options, ui::Ui};
use jj_lib::{
    fileset::{self, FilesetAliasesMap, FilesetDiagnostics, FilesetParseContext},
    gitignore::GitIgnoreFile,
    matchers::NothingMatcher,
    repo_path::{RepoPath, RepoPathUiConverter},
    settings::HumanByteSize,
    working_copy::{LockedWorkingCopy, SnapshotOptions},
};
use std::path::PathBuf;

fn ignores(path: &Path, repo: &ReadonlyRepo) -> Result<Arc<GitIgnoreFile>, BackendError> {
    let mut ignores = GitIgnoreFile::empty();
    if let Ok(backend) = git::get_git_backend(repo.store()) {
        let git_repo = backend.git_repo();
        let config = git_repo.config_snapshot();
        let global = if let Some(value) = config.string("core.excludesFile") {
            Some(path.join(jj_lib::file_util::expand_home_path(
                std::str::from_utf8(&value).map_err(read_error)?,
            )))
        } else {
            std::env::var_os("XDG_CONFIG_HOME")
                .filter(|dir| !dir.is_empty())
                .map(PathBuf::from)
                .or_else(|| std::env::home_dir().map(|home| home.join(".config")))
                .map(|dir| dir.join("git/ignore"))
        };
        if let Some(global) = global {
            ignores = ignores
                .chain_with_file(RepoPath::root(), global)
                .map_err(read_error)?;
        }
        ignores = ignores
            .chain_with_file(
                RepoPath::root(),
                backend.git_repo_path().join("info/exclude"),
            )
            .map_err(read_error)?;
    }
    Ok(ignores)
}

pub(super) async fn prepare(
    context: &WriteContext<'_>,
    repo: &Arc<ReadonlyRepo>,
    wc: &mut dyn LockedWorkingCopy,
    token: &BackendCancellation,
    receipt: &mut BackendWriteReceipt,
) -> Result<Arc<ReadonlyRepo>, BackendError> {
    let WriteContext {
        path,
        name,
        settings,
        heads,
        colocated,
    } = *context;
    let mut tx = repo.start_transaction();
    tx.set_is_snapshot(true);
    tx.set_workspace_name(name);
    let mut old_wc = working_commit(repo, name)?;
    if colocated {
        git::import_head(tx.repo_mut()).await.map_err(read_error)?;
        let head = tx.repo().view().git_head().clone();
        if &head != repo.view().git_head()
            && let Some(id) = head.as_normal()
        {
            let parent = repo.store().get_commit(id).map_err(read_error)?;
            old_wc = tx
                .repo_mut()
                .check_out(name.to_owned(), &parent)
                .await
                .map_err(read_error)?;
            wc.reset(&old_wc).await.map_err(read_error)?;
            tx.repo_mut()
                .rebase_descendants()
                .await
                .map_err(read_error)?;
        }
    }
    let aliases: FilesetAliasesMap = load_aliases_map(
        &Ui::null(),
        settings.config(),
        &"fileset-aliases".parse().unwrap(),
    )
    .map_err(|e| read_error(e.error))?;
    let paths = RepoPathUiConverter::Fs {
        base: path.into(),
        cwd: path.into(),
    };
    let ctx = FilesetParseContext {
        aliases_map: &aliases,
        path_converter: &paths,
    };
    let pattern = settings
        .get_string("snapshot.auto-track")
        .map_err(read_error)?;
    let matcher = fileset::parse(&mut FilesetDiagnostics::new(), &pattern, &ctx)
        .map_err(read_error)?
        .to_matcher();
    let HumanByteSize(limit) = settings
        .get_value_with("snapshot.max-new-file-size", TryInto::try_into)
        .map_err(read_error)?;
    let options = SnapshotOptions {
        base_ignores: ignores(path, repo)?,
        progress: None,
        start_tracking_matcher: matcher.as_ref(),
        force_tracking_matcher: &NothingMatcher,
        max_new_file_size: if limit == 0 { u64::MAX } else { limit },
    };
    let (tree, _stats) = wc.snapshot(&options).await.map_err(read_error)?;
    if tree.tree_ids_and_labels() != old_wc.tree().tree_ids_and_labels() {
        let new = tx
            .repo_mut()
            .rewrite_commit(&old_wc)
            .set_tree(tree.clone())
            .write()
            .await
            .map_err(read_error)?;
        tx.repo_mut()
            .set_wc_commit(name.to_owned(), new.id().clone())
            .map_err(read_error)?;
        tx.repo_mut()
            .rebase_descendants()
            .await
            .map_err(read_error)?;
    }
    if colocated {
        let options = load_git_import_options(
            &Ui::null(),
            &git::GitSettings::from_settings(settings).map_err(read_error)?,
            &settings.remote_settings().map_err(read_error)?,
        )
        .map_err(|e| read_error(e.error))?;
        git::import_refs(tx.repo_mut(), &options)
            .await
            .map_err(read_error)?;
        tx.repo_mut()
            .rebase_descendants()
            .await
            .map_err(read_error)?;
    }
    token.check()?;
    if !tx.repo().has_changes() {
        return Ok(repo.clone());
    }
    let prepared = publish(tx, "snapshot working copy", heads, receipt).await?;
    receipt.preparation_operation_id = Some(prepared.op_id().hex());
    receipt.working_copy = SyncStatus::Pending;
    let new_wc = working_commit(&prepared, name)?;
    if new_wc.tree().tree_ids_and_labels() != tree.tree_ids_and_labels() {
        wc.check_out(&new_wc).await.map_err(|err| {
            receipt.working_copy = SyncStatus::Failed;
            read_error(err)
        })?;
    }
    if colocated {
        receipt.git = SyncStatus::Pending;
        let result = async {
            git::update_intent_to_add(&**repo, &old_wc.tree(), &tree)
                .await
                .map_err(read_error)?;
            export(&prepared, name, &new_wc, heads, receipt).await
        }
        .await;
        receipt.git = if result.is_ok() {
            SyncStatus::Completed
        } else {
            SyncStatus::Failed
        };
        result
    } else {
        Ok(prepared)
    }
}

pub(super) async fn export(
    repo: &Arc<ReadonlyRepo>,
    name: &WorkspaceName,
    wc: &Commit,
    heads: &dyn OpHeadsStore,
    receipt: &mut BackendWriteReceipt,
) -> Result<Arc<ReadonlyRepo>, BackendError> {
    let mut tx = repo.start_transaction();
    tx.set_workspace_name(name);
    tx.set_attribute("ravel.git-sync".into(), repo.op_id().hex());
    git::reset_head(tx.repo_mut(), wc)
        .await
        .map_err(read_error)?;
    let stats = git::export_refs(tx.repo_mut()).map_err(read_error)?;
    let result = if tx.repo().has_changes() {
        publish(tx, "synchronize local Git state", heads, receipt).await?
    } else {
        repo.clone()
    };
    if !stats.failed_bookmarks.is_empty() || !stats.failed_tags.is_empty() {
        return Err(read_error(format!(
            "Git export failed: {:?} {:?}",
            stats.failed_bookmarks, stats.failed_tags
        )));
    }
    Ok(result)
}
