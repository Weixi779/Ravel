//
//  window_status.rs
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

use crate::{
    BackendCancellation, BackendError, BackendRepository, load_workspace, read_error,
    writer::preparation,
};
use jj_lib::{
    conflicts::{
        ConflictMaterializeOptions, MaterializedTreeValue, choose_materialized_conflict_marker_len,
        materialize_merge_result_to_bytes, materialize_tree_value,
    },
    local_working_copy::{
        EolConversionMode, ExecChangeSetting, FileType, LocalWorkingCopy, TreeStateSettings,
    },
    object_id::ObjectId,
    repo_path::{RepoPath, RepoPathBuf},
    working_copy::WorkingCopy,
};
use std::{
    collections::HashSet, fs, io, os::unix::fs::PermissionsExt, path::Path, sync::Arc,
    time::UNIX_EPOCH,
};

#[uniffi::export]
impl BackendRepository {
    pub async fn operation_heads(
        &self,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<Vec<String>, BackendError> {
        let root = self.path.clone();
        self.run_read(cancellation, move |token| {
            token.check()?;
            let workspace = load_workspace(&root)?;
            let heads = pollster::block_on(workspace.repo_loader().op_heads_store().get_op_heads())
                .map_err(read_error)?;
            Ok(heads.iter().map(ObjectId::hex).collect())
        })
        .await
    }

    pub async fn has_disk_changes(
        &self,
        changed_paths: Vec<String>,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<bool, BackendError> {
        let root = self.path.clone();
        self.run_read(cancellation, move |token| {
            pollster::block_on(disk_changes(&root, changed_paths, token))
        })
        .await
    }
}

async fn disk_changes(
    root: &Path,
    changed_paths: Vec<String>,
    token: &BackendCancellation,
) -> Result<bool, BackendError> {
    let changed: HashSet<_> = changed_paths
        .iter()
        .map(RepoPathBuf::from_relative_path)
        .collect::<Result<_, _>>()
        .map_err(read_error)?;
    let ancestors: HashSet<_> = changed.iter().flat_map(|p| p.ancestors()).collect();
    let in_scope = |p: &RepoPath| {
        changed.is_empty() || p.ancestors().any(|ancestor| changed.contains(ancestor))
    };
    let workspace = load_workspace(root)?;
    let wc = workspace
        .working_copy()
        .downcast_ref::<LocalWorkingCopy>()
        .ok_or_else(|| read_error("Working copy metadata is unavailable."))?;
    let states = wc.file_states().map_err(read_error)?;
    let tree = wc.tree().map_err(read_error)?;
    let patterns = wc.sparse_patterns().map_err(read_error)?;
    let settings =
        TreeStateSettings::try_from_user_settings(workspace.settings()).map_err(read_error)?;
    let loader = workspace.repo_loader();
    let op = loader
        .load_operation(wc.operation_id())
        .await
        .map_err(read_error)?;
    let repo = loader.load_at(&op).await.map_err(read_error)?;
    let (matcher, limit) = preparation::tracking_policy(root, workspace.settings())?;
    let mut dirs = vec![(
        RepoPathBuf::root(),
        preparation::ignores(root, &repo)?,
        false,
    )];
    let mut seen = HashSet::new();
    while let Some((dir, parent_ignores, ignored_parent)) = dirs.pop() {
        token.check()?;
        let disk_dir = dir.to_fs_path(root).map_err(read_error)?;
        let ignores = parent_ignores
            .chain_with_file(&dir, disk_dir.join(".gitignore"))
            .map_err(read_error)?;
        let Some(entries) = if_present(fs::read_dir(&disk_dir))? else {
            continue;
        };
        for entry in entries {
            token.check()?;
            let Some(entry) = if_present(entry)? else {
                continue;
            };
            if entry.file_name() == ".git" || entry.file_name() == ".jj" {
                continue;
            }
            let disk_path = entry.path();
            let path =
                RepoPathBuf::from_relative_path(disk_path.strip_prefix(root).map_err(read_error)?)
                    .map_err(read_error)?;
            if !in_scope(&path) && !ancestors.contains(&*path) {
                continue;
            }
            let Some(kind) = if_present(entry.file_type())? else {
                continue;
            };
            if kind.is_dir() {
                if states
                    .get(&path)
                    .is_some_and(|state| matches!(state.file_type, FileType::GitSubmodule))
                {
                    seen.insert(path);
                    continue;
                }
                let ignored = ignored_parent || ignores.matches_dir(&path);
                if (!ignored || !states.prefixed(&path).is_empty())
                    && patterns
                        .iter()
                        .any(|p| path.starts_with(p) || p.starts_with(&path))
                {
                    dirs.push((path, ignores.clone(), ignored));
                }
                continue;
            }
            if !kind.is_file() && !kind.is_symlink() {
                continue;
            }
            let Some(meta) = if_present(fs::symlink_metadata(&disk_path))? else {
                continue;
            };
            let Some(state) = states.get(&path) else {
                if !ignored_parent
                    && !ignores.matches_file(&path)
                    && patterns.iter().any(|p| path.starts_with(p))
                    && matcher.matches(&path)
                    && (limit == 0 || meta.len() <= limit)
                {
                    return Ok(true);
                }
                continue;
            };
            let mtime = meta
                .modified()
                .ok()
                .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                .map(|t| t.as_millis() as i64);
            let cached = !changed.contains(&path)
                && mtime == Some(state.mtime.0)
                && meta.len() == state.size;
            let value = tree.path_value(&path).await.map_err(read_error)?;
            let mode_changed = |executable: bool| {
                !matches!(settings.exec_change_setting, ExecChangeSetting::Ignore)
                    && (meta.permissions().mode() & 0o111 != 0) != executable
            };
            if let Some(Some(jj_lib::backend::TreeValue::File { executable, .. })) =
                value.as_resolved()
            {
                if !kind.is_file()
                    || mode_changed(*executable)
                    || (state.mtime.0 != 0
                        && settings.eol_conversion_mode == EolConversionMode::None
                        && meta.len() != state.size)
                {
                    return Ok(true);
                }
                if cached {
                    seen.insert(path);
                    continue;
                }
            }
            match materialize_tree_value(tree.store(), &path, value, tree.labels())
                .await
                .map_err(read_error)?
            {
                MaterializedTreeValue::File(mut file) => {
                    if !kind.is_file() || mode_changed(file.executable) {
                        return Ok(true);
                    }
                    let stored = file.read_all(&path).await.map_err(read_error)?;
                    if !matches_disk(&disk_path, &stored, settings.eol_conversion_mode)? {
                        return Ok(true);
                    }
                }
                MaterializedTreeValue::Symlink { target, .. } => {
                    if !kind.is_symlink()
                        || if_present(fs::read_link(&disk_path))?.as_deref()
                            != Some(Path::new(&target))
                    {
                        return Ok(true);
                    }
                }
                MaterializedTreeValue::FileConflict(file) => {
                    if !kind.is_file() || mode_changed(file.executable.unwrap_or(false)) {
                        return Ok(true);
                    }
                    if !cached {
                        let options = ConflictMaterializeOptions {
                            marker_style: settings.conflict_marker_style,
                            marker_len: Some(choose_materialized_conflict_marker_len(
                                &file.contents,
                            )),
                            merge: tree.store().merge_options().clone(),
                        };
                        let stored = materialize_merge_result_to_bytes(
                            &file.contents,
                            &file.labels,
                            &options,
                        );
                        if !matches_disk(&disk_path, &stored, settings.eol_conversion_mode)? {
                            return Ok(true);
                        }
                    }
                }
                MaterializedTreeValue::AccessDenied(err) => return Err(read_error(err)),
                MaterializedTreeValue::OtherConflict { .. } if cached => (),
                _ => return Ok(true),
            }
            seen.insert(path);
        }
    }
    if changed.is_empty() {
        return Ok(states.paths().any(|path| !seen.contains(path)));
    }
    Ok(changed
        .iter()
        .any(|p| states.prefixed(p).paths().any(|path| !seen.contains(path))))
}

fn if_present<T>(result: io::Result<T>) -> Result<Option<T>, BackendError> {
    match result {
        Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(None),
        result => result.map(Some).map_err(read_error),
    }
}

fn matches_disk(path: &Path, stored: &[u8], mode: EolConversionMode) -> Result<bool, BackendError> {
    let bytes = match fs::read(path) {
        Err(err) if err.kind() == io::ErrorKind::NotFound => return Ok(false),
        result => result.map_err(read_error)?,
    };
    if bytes == stored {
        return Ok(true);
    }
    if mode == EolConversionMode::None {
        return Ok(false);
    }
    let probe = &bytes[..bytes.len().min(8192)];
    if probe
        .iter()
        .enumerate()
        .any(|(i, b)| *b == 0 || (*b == b'\r' && bytes.get(i + 1) != Some(&b'\n')))
    {
        return Ok(false);
    }
    Ok(bytes
        .iter()
        .enumerate()
        .filter_map(|(i, b)| (*b != b'\r' || bytes.get(i + 1) != Some(&b'\n')).then_some(*b))
        .eq(stored.iter().copied()))
}
