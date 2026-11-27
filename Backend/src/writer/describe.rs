//
//  describe.rs
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

use super::*;

pub(super) async fn rewrite(
    context: &WriteContext<'_>,
    repo: &Arc<ReadonlyRepo>,
    tx: &mut Transaction,
    target: BackendWriteTarget,
    description: String,
    receipt: &mut BackendWriteReceipt,
) -> Result<Option<(String, Option<Commit>)>, BackendError> {
    let id = CommitId::try_from_hex(&target.commit_id)
        .filter(|id| id.as_bytes().len() == repo.store().commit_id_length())
        .ok_or_else(|| read_error("Invalid commit ID"))?;
    let origin_id = jj_lib::op_store::OperationId::try_from_hex(&target.operation_id)
        .ok_or_else(|| read_error("Invalid operation ID"))?;
    let loader = repo.loader();
    let origin = loader
        .load_at(
            &loader
                .load_operation(&origin_id)
                .await
                .map_err(read_error)?,
        )
        .await
        .map_err(read_error)?;
    let commit = repo.store().get_commit(&id).map_err(read_error)?;
    let change = commit.change_id();
    let versions = |r: &ReadonlyRepo| -> Result<_, BackendError> {
        Ok(r.resolve_change_id(change)
            .map_err(read_error)?
            .and_then(|ids| ids.into_visible())
            .unwrap_or_default()
            .into_iter()
            .collect::<std::collections::BTreeSet<_>>())
    };
    let initial = versions(&origin)?;
    if change.reverse_hex() != target.change_id
        || !initial.contains(&id)
        || initial != versions(repo)?
    {
        return Err(receipt.reject(
            WriteDisposition::StaleTarget,
            "The selected revision changed. Refresh and review it again.",
        ));
    }
    if &id == repo.store().root_commit_id()
        || crate::history::immutable_revisions_at(
            context.path,
            context.name,
            context.settings,
            repo,
        )?
        .containing_fn()(&id)
        .map_err(read_error)?
    {
        return Err(receipt.reject(
            WriteDisposition::Immutable,
            "The repository marks this revision immutable.",
        ));
    }
    receipt.commit_id = Some(id.hex());
    receipt.change_id = Some(change.reverse_hex());
    if commit.description() == description {
        return Ok(None);
    }
    receipt.phase = WritePhase::Mutating;
    let new = tx
        .repo_mut()
        .rewrite_commit(&commit)
        .set_description(description)
        .write()
        .await
        .map_err(read_error)?;
    tx.repo_mut()
        .rebase_descendants()
        .await
        .map_err(read_error)?;
    Ok(Some((format!("describe commit {}", id.hex()), Some(new))))
}
