//
//  RepositoryWorkspace.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation

/// The composition owner of the currently opened repository. Feature sessions
/// receive queries; they do not construct or share native repository handles.
actor RepositoryWorkspace {
    private var repository: CodeRepository?
    private var requestedURL: URL?
    private var generation = 0
    private var retiredReceipts: [RepositoryWriteReceipt] = []
    private var retirements: [UUID: Task<Void, Never>] = [:]

    func history(at url: URL, pageSize: Int) async throws -> any HistoryQuery {
        generation += 1
        let request = generation
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        if let repository, requestedURL == normalized || repository.workspaceURL.standardizedFileURL.resolvingSymlinksInPath().path == normalized.path {
            return try await repository.history(pageSize: pageSize)
        }
        let candidate = try await CodeRepository.open(normalized)
        guard request == generation, !Task.isCancelled else {
            await candidate.close()
            throw CancellationError()
        }
        let previous = repository
        repository = candidate
        requestedURL = normalized
        await retire(previous)
        return try await candidate.history(pageSize: pageSize)
    }

    func close() async {
        generation += 1
        let previous = repository
        repository = nil
        requestedURL = nil
        await retire(previous)
        for pending in Array(retirements.values) { await pending.value }
    }

    private func retire(_ previous: CodeRepository?) async {
        guard let previous else { return }
        let id = UUID()
        let task = Task {
            await previous.close()
            retiredReceipts.append(contentsOf: previous.takeWriteReceipts())
            retirements.removeValue(forKey: id)
        }
        retirements[id] = task
        await task.value
    }

    func takeWriteReceipts() -> [RepositoryWriteReceipt] {
        defer { retiredReceipts.removeAll() }
        return retiredReceipts + (repository?.takeWriteReceipts() ?? [])
    }

    func describe(_ target: RevisionWriteTarget, title: String, body: String) async throws -> RepositoryWriteReceipt {
        try await current(at: target.workspaceURL).describe(target, title: title, body: body)
    }

    func apply(_ command: RevisionGraphCommand, to source: RevisionWriteTarget) async throws -> RepositoryWriteReceipt {
        try await current(at: source.workspaceURL).apply(command, to: source)
    }

    func snapshot(at workspaceURL: URL, operationID: String) async throws -> RepositoryWriteReceipt {
        try await current(at: workspaceURL).snapshot(operationID: operationID)
    }

    func operationHistory(at workspaceURL: URL, limit: UInt32 = 50) async throws -> RepositoryOperationHistory {
        try await current(at: workspaceURL).operationHistory(limit: limit)
    }

    func undo(_ history: RepositoryOperationHistory) async throws -> RepositoryWriteReceipt {
        try await current(at: history.workspaceURL).undo(history)
    }

    func diff(_ request: RevisionDiffRequest) async throws -> RevisionDiff {
        try await current(at: request.repositoryURL).diff(commitID: request.commitID, at: request.operationID)
    }

    func fileDiff(_ request: RevisionDiffRequest, file: ChangedFile) async throws -> FileDiff {
        try await current(at: request.repositoryURL).fileDiff(commitID: request.commitID, path: file.path, at: request.operationID)
    }

    func diffStatistics(_ request: RevisionDiffRequest) async throws -> RevisionDiffStatistics {
        try await current(at: request.repositoryURL).diffStatistics(commitID: request.commitID, at: request.operationID)
    }

    private func current(at workspaceURL: URL) throws -> CodeRepository {
        let normalized = workspaceURL.standardizedFileURL.resolvingSymlinksInPath()
        guard let repository, repository.workspaceURL.standardizedFileURL.resolvingSymlinksInPath().path == normalized.path else { throw CancellationError() }
        return repository
    }
}
