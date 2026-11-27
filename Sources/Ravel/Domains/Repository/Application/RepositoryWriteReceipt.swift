//
//  RepositoryWriteReceipt.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
import RavelBackend

nonisolated struct RevisionWriteTarget: Sendable {
    let workspaceURL: URL
    let operationID: String
    let commitID: String
    let changeID: String
}

nonisolated struct RepositoryWriteReceipt: Sendable {
    let requestID: String
    let workspaceURL: URL
    let initialOperationID: String
    let preparationOperationID: String?
    let mutationOperationID: String?
    let currentOperationID: String?
    let commitID: String?
    let changeID: String?
    let disposition: WriteDisposition
    let phase: WritePhase
    let cancellationPhase: WritePhase?
    let workingCopy: SyncStatus
    let git: SyncStatus
    let detail: String?

    init(_ native: BackendWriteReceipt) {
        requestID = native.requestId
        workspaceURL = URL(fileURLWithPath: native.workspacePath, isDirectory: true)
        initialOperationID = native.initialOperationId
        preparationOperationID = native.preparationOperationId
        mutationOperationID = native.mutationOperationId
        currentOperationID = native.currentOperationId
        commitID = native.commitId
        changeID = native.changeId
        disposition = native.disposition
        phase = native.phase
        cancellationPhase = native.cancellationPhase
        workingCopy = native.workingCopy
        git = native.git
        detail = native.detail
    }
}

nonisolated struct RepositoryOperation: Identifiable, Sendable {
    let id: String
    let description: String
    let date: Date
    let workspace: String?

    init(_ native: BackendOperation) {
        id = native.id
        description = native.description
        date = Date(timeIntervalSince1970: Double(native.timestampMillis) / 1000)
        workspace = native.workspaceName
    }
}

nonisolated struct RepositoryOperationHistory: Sendable {
    let workspaceURL: URL
    let headID: String
    let entries: [RepositoryOperation]
    let undoTarget: RepositoryOperation?
}
