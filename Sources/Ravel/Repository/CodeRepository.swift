// Created by weixi on 2026/09/17.

import Foundation
import RavelBackend

/// Application-facing read capability. Rust handles never escape this adapter.
nonisolated protocol CodeRepositoryReader: Sendable {
    func history(pageSize: Int) async throws -> any HistoryQuery
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

nonisolated final class CodeRepository: CodeRepositoryReader {
    let workspaceURL: URL
    let repositoryURL: URL
    private let backend: BackendRepository

    private init(backend: BackendRepository) {
        self.backend = backend
        let identity = backend.identity()
        workspaceURL = URL(fileURLWithPath: identity.workspacePath, isDirectory: true)
        repositoryURL = URL(fileURLWithPath: identity.repositoryPath, isDirectory: true)
    }

    @concurrent static func open(_ url: URL) async throws -> CodeRepository {
        try Task.checkCancellation()
        let repository = try CodeRepository(backend: backendRead { try BackendRepository.open(path: url.path) })
        if Task.isCancelled {
            repository.backend.close()
            throw CancellationError()
        }
        return repository
    }

    @concurrent func history(pageSize: Int) async throws -> any HistoryQuery {
        guard (1...5000).contains(pageSize) else { throw RepositoryReadFailure(message: "Invalid history page size") }
        let cancellation = BackendCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let query = try backendRead { try backend.history(pageSize: UInt32(pageSize), cancellation: cancellation) }
            if Task.isCancelled {
                query.close()
                throw CancellationError()
            }
            return RustHistoryQuery(backend: query)
        } onCancel: { cancellation.cancel() }
    }

    @concurrent func close() async { backend.close() }
}

nonisolated private final class RustHistoryQuery: HistoryQuery {
    let identity: HistoryIdentity
    private let backend: BackendHistory

    init(backend: BackendHistory) {
        self.backend = backend
        let info = backend.info()
        identity = HistoryIdentity(queryID: UUID(), operationID: info.operationId,
                                   repositoryURL: URL(fileURLWithPath: info.workspacePath, isDirectory: true),
                                   backendVersion: info.backendVersion)
    }

    @concurrent func page(after cursor: HistoryCursor?) async throws -> HistoryPage {
        if let cursor, cursor.queryID != identity.queryID { throw BackendError.InvalidCursor }
        let cancellation = BackendCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let page = try backendRead { try backend.page(cursor: cursor?.offset ?? 0, cancellation: cancellation) }
            try Task.checkCancellation()
            return HistoryPage(revisions: page.revisions.map(Revision.init), nextCursor: page.nextCursor.map {
                HistoryCursor(queryID: identity.queryID, offset: $0)
            })
        } onCancel: { cancellation.cancel() }
    }

    @concurrent func close() async { backend.close() }
}

nonisolated private extension Revision {
    init(_ value: BackendRevision) {
        self.init(commitID: value.commitId, changeID: value.changeId, parentIDs: value.parentIds,
                  description: value.description, author: value.author, email: value.email,
                  timestamp: Date(timeIntervalSince1970: Double(value.timestampMillis) / 1000),
                  bookmarks: value.bookmarks, isWorkingCopy: value.isWorkingCopy, isImmutable: value.isImmutable,
                  hasConflict: value.hasConflict, isDivergent: value.isDivergent, isEmpty: value.isEmpty)
    }
}

nonisolated private struct RepositoryReadFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

nonisolated private func backendRead<T>(_ operation: () throws -> T) throws -> T {
    do { return try operation() }
    catch BackendError.Read(let message) { throw RepositoryReadFailure(message: message) }
    catch BackendError.Cancelled { throw CancellationError() }
}
