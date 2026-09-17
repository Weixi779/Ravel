// Created by weixi on 2026/09/17.

import Foundation

/// The composition owner of the currently opened repository. Feature sessions
/// receive queries; they do not construct or share native repository handles.
actor RepositoryWorkspace {
    private var repository: CodeRepository?
    private var requestedURL: URL?
    private var generation = 0

    func history(at url: URL, pageSize: Int) async throws -> any HistoryQuery {
        generation += 1
        let request = generation
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        if let repository, requestedURL == normalized || repository.workspaceURL == normalized {
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
        await previous?.close()
        return try await candidate.history(pageSize: pageSize)
    }

    func close() async {
        generation += 1
        let previous = repository
        repository = nil
        requestedURL = nil
        await previous?.close()
    }
}
