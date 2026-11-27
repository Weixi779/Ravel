//
//  organize.rs
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

use super::*;
use crate::BackendFileSelection;

#[uniffi::export]
impl BackendRepository {
    pub async fn split(
        &self,
        request_id: String,
        source: BackendWriteTarget,
        selection: Vec<BackendFileSelection>,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<BackendWriteReceipt, BackendError> {
        self.submit(
            request_id,
            Command::Split(source, selection),
            cancellation,
            false,
        )
        .await
    }

    pub async fn squash(
        &self,
        request_id: String,
        source: BackendWriteTarget,
        destination: BackendWriteTarget,
        paths: Option<Vec<String>>,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<BackendWriteReceipt, BackendError> {
        self.submit(
            request_id,
            Command::Squash(source, destination, paths),
            cancellation,
            false,
        )
        .await
    }

    pub async fn resolve_file(
        &self,
        request_id: String,
        source: BackendWriteTarget,
        path: String,
        cancellation: Arc<BackendCancellation>,
    ) -> Result<BackendWriteReceipt, BackendError> {
        self.submit(
            request_id,
            Command::Resolve {
                target: source,
                path,
                resolved: None,
            },
            cancellation,
            false,
        )
        .await
    }
}
