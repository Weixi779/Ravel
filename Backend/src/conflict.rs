//
//  conflict.rs
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

use crate::{BackendError, read_error};
use jj_cli::{config::CommandNameAndArgs, merge_tools::MergeEditor, ui::Ui};
use jj_lib::{
    commit::Commit,
    config::{ConfigGetResultExt, ConfigLayer, ConfigSource},
    merged_tree::MergedTree,
    repo_path::{RepoPath, RepoPathUiConverter},
    settings::UserSettings,
};
use std::path::Path;

pub(crate) async fn edit(
    workspace: &Path,
    settings: &UserSettings,
    source: &Commit,
    path: &str,
) -> Result<MergedTree, BackendError> {
    let path = RepoPath::from_internal_string(path).map_err(read_error)?;
    let tree = source.tree();
    if tree
        .path_value(path)
        .await
        .map_err(read_error)?
        .is_resolved()
    {
        return Err(read_error(
            "This path no longer has a conflict. Refresh and review.",
        ));
    }
    let editor = external_editor(workspace, settings)?;
    let (resolved, error) = editor
        .edit_files(&Ui::null(), &tree, &[path])
        .await
        .map_err(read_error)?;
    if let Some(error) = error {
        return Err(read_error(error));
    }
    if resolved.tree_ids_and_labels() == tree.tree_ids_and_labels() {
        return Err(read_error(
            "The tool closed with the conflict still unresolved.",
        ));
    }
    Ok(resolved)
}

fn external_editor(path: &Path, settings: &UserSettings) -> Result<MergeEditor, BackendError> {
    let paths = RepoPathUiConverter::Fs {
        cwd: path.into(),
        base: path.into(),
    };
    let markers = settings
        .get("ui.conflict-marker-style")
        .map_err(read_error)?;
    let configured: Option<CommandNameAndArgs> = settings
        .get("ui.merge-editor")
        .optional()
        .map_err(read_error)?;
    if configured.is_some_and(|tool| !tool.as_str().is_some_and(|name| name.starts_with(':'))) {
        return MergeEditor::from_settings(&Ui::null(), settings, paths, markers)
            .map_err(read_error);
    }
    // Without a configured GUI merge tool, give TextEdit a private conflict-marker file.
    // open -W waits for this dedicated instance to quit before jj reads its result.
    let mut config = settings.config().clone();
    config.add_layer(
        ConfigLayer::parse(
            ConfigSource::CommandArg,
            r#"
        [merge-tools.ravel-textedit]
        program = "/usr/bin/open"
        merge-args = ["-W", "-n", "-a", "TextEdit", "$output"]
        merge-tool-edits-conflict-markers = true
    "#,
        )
        .map_err(read_error)?,
    );
    let fallback = settings.with_new_config(config).map_err(read_error)?;
    MergeEditor::with_name("ravel-textedit", &fallback, paths, markers).map_err(read_error)
}
