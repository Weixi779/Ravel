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
    let commit = target::resolve(context, repo, &target, true, receipt).await?;
    let id = commit.id();
    let change = commit.change_id();
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
