//
//  CodeRepository.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
import RavelBackend

/// Application-facing read capability. Rust handles never escape this adapter.
nonisolated protocol CodeRepositoryReader: Sendable {
    func history(pageSize: Int) async throws -> any HistoryQuery
    func diff(commitID: String, at operationID: String) async throws -> RevisionDiff
    func fileDiff(commitID: String, path: String, at operationID: String) async throws -> FileDiff
    func diffStatistics(commitID: String, at operationID: String) async throws -> RevisionDiffStatistics
    func close() async
}

nonisolated struct HistoryIdentity: Sendable {
    let queryID: UUID
    let operationID: String
    let repositoryURL: URL
    let backendVersion: String
}

nonisolated struct HistoryCursor: Equatable, Sendable {
    let queryID: UUID
    let offset: UInt64
}

nonisolated struct HistoryPage: Sendable {
    let revisions: [Revision]
    let nextCursor: HistoryCursor?
}

nonisolated protocol HistoryQuery: Sendable {
    var identity: HistoryIdentity { get }
    func page(after cursor: HistoryCursor?) async throws -> HistoryPage
    func close() async
}

nonisolated protocol CodeRepositoryWriter: Sendable {
    func describe(_ target: RevisionWriteTarget, title: String, body: String) async throws -> RepositoryWriteReceipt
    func snapshot(operationID: String) async throws -> RepositoryWriteReceipt
    func undo(_ history: RepositoryOperationHistory) async throws -> RepositoryWriteReceipt
}

final nonisolated class CodeRepository: CodeRepositoryReader, CodeRepositoryWriter {
    let workspaceURL: URL
    let repositoryURL: URL
    private let backend: BackendRepository

    private init(backend: BackendRepository) {
        self.backend = backend
        let identity = backend.identity()
        workspaceURL = URL(fileURLWithPath: identity.workspacePath, isDirectory: true)
        repositoryURL = URL(fileURLWithPath: identity.repositoryPath, isDirectory: true)
    }

    @concurrent
    static func open(_ url: URL) async throws -> CodeRepository {
        try Task.checkCancellation()
        let backend = try await backendRead { try await BackendRepository.open(path: url.path) }
        let repository = CodeRepository(backend: backend)
        if Task.isCancelled {
            await repository.backend.close()
            throw CancellationError()
        }
        return repository
    }

    @concurrent
    func history(pageSize: Int) async throws -> any HistoryQuery {
        guard (1 ... 5000).contains(pageSize) else { throw RepositoryReadFailure(message: "Invalid history page size") }
        let cancellation = BackendCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let query = try await backendRead { try await backend.history(pageSize: UInt32(pageSize), cancellation: cancellation) }
            if Task.isCancelled {
                await query.close()
                throw CancellationError()
            }
            return RustHistoryQuery(backend: query)
        } onCancel: { cancellation.cancel() }
    }

    @concurrent
    func describe(_ target: RevisionWriteTarget, title: String, body: String) async throws -> RepositoryWriteReceipt {
        guard target.workspaceURL.standardizedFileURL.resolvingSymlinksInPath().path == workspaceURL.standardizedFileURL.resolvingSymlinksInPath().path else { throw BackendError.Closed }
        let target = BackendWriteTarget(operationId: target.operationID, commitId: target.commitID, changeId: target.changeID)
        var description = title
        if !body.isEmpty { description += "\n\n" + body }
        if !description.isEmpty, !description.hasSuffix("\n") { description += "\n" }
        let message = description
        return try await write { id, token in
            try await self.backend.describe(requestId: id, target: target, description: message, cancellation: token)
        }
    }

    @concurrent
    func snapshot(operationID: String) async throws -> RepositoryWriteReceipt {
        try await write { id, token in
            try await self.backend.snapshot(requestId: id, operationId: operationID, cancellation: token)
        }
    }

    @concurrent
    func operationHistory(limit: UInt32) async throws -> RepositoryOperationHistory {
        let token = BackendCancellation()
        return try await withTaskCancellationHandler {
            let result = try await backendRead { try await backend.operationHistory(limit: limit, cancellation: token) }
            return RepositoryOperationHistory(workspaceURL: workspaceURL, headID: result.headId, entries: result.entries.map(RepositoryOperation.init), undoTarget: result.undoTarget.map(RepositoryOperation.init))
        } onCancel: { token.cancel() }
    }

    @concurrent
    func undo(_ history: RepositoryOperationHistory) async throws -> RepositoryWriteReceipt {
        guard history.workspaceURL == workspaceURL, let target = history.undoTarget else { throw BackendError.Closed }
        return try await write { id, token in
            try await self.backend.undo(requestId: id, headId: history.headID, operationId: target.id, cancellation: token)
        }
    }

    private func write(_ perform: @Sendable (String, BackendCancellation) async throws -> BackendWriteReceipt) async throws -> RepositoryWriteReceipt {
        let token = BackendCancellation()
        return try await withTaskCancellationHandler {
            try await RepositoryWriteReceipt(perform(UUID().uuidString, token))
        } onCancel: { token.cancel() }
    }

    func takeWriteReceipts() -> [RepositoryWriteReceipt] {
        backend.takeWriteReceipts().map(RepositoryWriteReceipt.init)
    }

    @concurrent
    func close() async {
        await backend.close()
    }

    @concurrent
    func diff(commitID: String, at operationID: String) async throws -> RevisionDiff {
        let cancellation = BackendCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let files = try await backendRead {
                try await backend.diff(operationId: operationID, commitId: commitID, cancellation: cancellation)
            }
            try Task.checkCancellation()
            return RevisionDiff(files: files.map(ChangedFile.init))
        } onCancel: { cancellation.cancel() }
    }

    @concurrent
    func fileDiff(commitID: String, path: String, at operationID: String) async throws -> FileDiff {
        let cancellation = BackendCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let patch = try await backendRead {
                try await backend.fileDiff(operationId: operationID, commitId: commitID, filePath: path, cancellation: cancellation)
            }
            try Task.checkCancellation()
            return try RevisionPatchParser.parse(patch)
        } onCancel: { cancellation.cancel() }
    }

    @concurrent
    func diffStatistics(commitID: String, at operationID: String) async throws -> RevisionDiffStatistics {
        let cancellation = BackendCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let statistics = try await backendRead {
                try await backend.diffStatistics(operationId: operationID, commitId: commitID, cancellation: cancellation)
            }
            try Task.checkCancellation()
            return RevisionDiffStatistics(
                files: Dictionary(uniqueKeysWithValues: statistics.files.map {
                    ($0.path, FileChangeStatistics(additions: $0.linesAdded.map(Int.init), deletions: $0.linesRemoved.map(Int.init), bytesDelta: Int($0.bytesDelta)))
                }),
                additions: Int(statistics.linesAdded),
                deletions: Int(statistics.linesRemoved),
                binaryFiles: Int(statistics.binaryFiles),
            )
        } onCancel: { cancellation.cancel() }
    }
}

private final nonisolated class RustHistoryQuery: HistoryQuery {
    let identity: HistoryIdentity
    private let backend: BackendHistory

    init(backend: BackendHistory) {
        self.backend = backend
        let info = backend.info()
        identity = HistoryIdentity(
            queryID: UUID(),
            operationID: info.operationId,
            repositoryURL: URL(fileURLWithPath: info.workspacePath, isDirectory: true),
            backendVersion: info.backendVersion,
        )
    }

    @concurrent
    func page(after cursor: HistoryCursor?) async throws -> HistoryPage {
        if let cursor, cursor.queryID != identity.queryID { throw BackendError.InvalidCursor }
        let cancellation = BackendCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let page = try await backendRead { try await backend.page(cursor: cursor?.offset ?? 0, cancellation: cancellation) }
            try Task.checkCancellation()
            return HistoryPage(revisions: page.revisions.map(Revision.init), nextCursor: page.nextCursor.map {
                HistoryCursor(queryID: identity.queryID, offset: $0)
            })
        } onCancel: { cancellation.cancel() }
    }

    @concurrent
    func close() async {
        await backend.close()
    }
}

private nonisolated extension Revision {
    init(_ value: BackendRevision) {
        self.init(
            commitID: value.commitId,
            changeID: value.changeId,
            parentIDs: value.parentIds,
            description: value.description,
            author: value.author,
            email: value.email,
            timestamp: Date(timeIntervalSince1970: Double(value.timestampMillis) / 1000),
            bookmarks: value.bookmarks,
            isWorkingCopy: value.isWorkingCopy,
            isImmutable: value.isImmutable,
            hasConflict: value.hasConflict,
            isDivergent: value.isDivergent,
            isEmpty: value.isEmpty,
        )
    }
}

private nonisolated extension ChangedFile {
    init(_ value: BackendChangedFile) {
        let status: Status = switch value.status {
        case .modified: .modified
        case .added: .added
        case .removed: .removed
        case .copied: .copied
        case .renamed: .renamed
        case .unchanged: .unchanged
        }
        self.init(
            path: value.path,
            sourcePath: value.sourcePath,
            status: status,
            before: value.before.map(FileMetadata.init),
            after: value.after.map(FileMetadata.init),
        )
    }
}

private nonisolated extension FileMetadata {
    init(_ value: BackendFileMetadata) {
        let kind: Kind = switch value.kind {
        case .file: .file
        case .symlink: .symlink
        case .directory: .directory
        case .submodule: .submodule
        case .conflict: .conflict
        }
        self.init(kind: kind, executable: value.executable, conflictSides: Int(value.conflictSides))
    }
}

private nonisolated struct RepositoryReadFailure: LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}

private nonisolated func backendRead<T>(_ operation: () async throws -> T) async throws -> T {
    do { return try await operation() }
    catch let BackendError.Read(message) { throw RepositoryReadFailure(message: message) }
    catch BackendError.Cancelled { throw CancellationError() }
    catch BackendError.DiffTooLarge { throw FileDiff.Failure.tooLarge }
}
