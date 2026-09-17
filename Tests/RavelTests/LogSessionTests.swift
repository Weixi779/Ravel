// Created by weixi on 2026/09/09.

import Foundation
import Observation
import Synchronization
import Testing
@testable import Ravel

@MainActor
struct LogSessionTests {
    @Test func supersededRequestCannotReplaceTheNewRepository() async throws {
        let gate = LoaderGate()
        let suite = "RavelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = LogSession(defaults: defaults) { url, _ in try await gate.load(url) }

        session.open(URL(fileURLWithPath: "/old"))
        await gate.waitForRequest("/old")
        session.open(URL(fileURLWithPath: "/new"))
        await gate.waitForRequest("/new")
        await gate.finish("/new", with: try repositoryLog("/new", revisions: [revision("new", workingCopy: true)]))
        try await waitUntil { !session.isLoading }
        await gate.finish("/old", with: try repositoryLog("/old", revisions: [revision("old")]))
        await gate.waitUntilReturned("/old")
        // The obsolete loader deliberately ignores cancellation; the session must not.
        #expect(session.repositoryURL?.path == "/new")
        #expect(session.log?.revisions.first?.id == "new")
        #expect(session.selectedRevisionID == "new")
        #expect(defaults.string(forKey: "lastRepositoryPath") == "/new")
    }

    @Test func failedRefreshKeepsThePreviouslyLoadedLog() async throws {
        let gate = LoaderGate()
        let suite = "RavelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = LogSession(defaults: defaults) { url, _ in try await gate.load(url) }
        session.open(URL(fileURLWithPath: "/repo"))
        await gate.waitForRequest("/repo")
        await gate.finish("/repo", with: try repositoryLog("/repo", revisions: [revision("saved")]))
        try await waitUntil { !session.isLoading }
        session.refresh()
        await gate.waitForRequest("/repo")
        await gate.fail("/repo")
        try await waitUntil { !session.isLoading }
        #expect(session.log?.revisions.first?.id == "saved")
        #expect(session.errorMessage != nil)
    }

    @Test func changingCLIExecutableUpdatesDiffWithoutReloadingHistory() async throws {
        let suite = "RavelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = try StubHistory(log: repositoryLog("/repo", revisions: [revision("saved")]))
        let session = LogSession(defaults: defaults) { _, _ in history }
        session.open(URL(fileURLWithPath: "/repo"))
        try await waitUntil { !session.isLoading }
        let snapshot = try #require(session.log?.snapshotID)
        let request = try #require(session.diffRequest)
        let changes = Mutex(0)
        withObservationTracking {
            _ = session.diffRequest
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        session.setExecutable(URL(fileURLWithPath: "/new/jj"))

        #expect(changes.withLock { $0 } == 1)
        #expect(session.diffRequest?.executablePath == "/new/jj")
        #expect(session.diffRequest?.operationID == request.operationID)
        #expect(!session.isLoading)
        #expect(session.log?.snapshotID == snapshot)
        #expect(await history.requests == [0])
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(condition(), "Session did not finish its request")
    }
}

private actor LoaderGate {
    private var pending: [String: CheckedContinuation<any HistoryQuery, any Error>] = [:]
    private var startedWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var returned = Set<String>()
    private var returnWaiters: [String: CheckedContinuation<Void, Never>] = [:]

    func load(_ url: URL) async throws -> any HistoryQuery {
        let result = try await withCheckedThrowingContinuation { continuation in
            pending[url.path] = continuation
            startedWaiters.removeValue(forKey: url.path)?.resume()
        }
        returned.insert(url.path)
        returnWaiters.removeValue(forKey: url.path)?.resume()
        return result
    }

    func waitForRequest(_ path: String) async {
        guard pending[path] == nil else { return }
        await withCheckedContinuation { startedWaiters[path] = $0 }
    }

    func finish(_ path: String, with log: RepositoryLog) {
        pending.removeValue(forKey: path)?.resume(returning: StubHistory(log: log))
    }

    func fail(_ path: String) {
        pending.removeValue(forKey: path)?.resume(throwing: JJClient.Failure.commandFailed("Failed refresh"))
    }

    func waitUntilReturned(_ path: String) async {
        guard !returned.contains(path) else { return }
        await withCheckedContinuation { returnWaiters[path] = $0 }
    }
}
