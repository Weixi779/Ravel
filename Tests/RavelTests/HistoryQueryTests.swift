// Created by weixi on 2026/09/17.

import Foundation
@testable import Ravel
import Testing

actor StubHistory: HistoryQuery {
    nonisolated let identity: HistoryIdentity
    private let revisions: [Revision]
    private let pageSize: Int
    private var paused = Set<UInt64>()
    private var pending: [UInt64: CheckedContinuation<HistoryPage, any Error>] = [:]
    private var waiters: [UInt64: CheckedContinuation<Void, Never>] = [:]
    private(set) var requests: [UInt64] = []
    private(set) var isClosed = false

    init(log: RepositoryLog, pageSize: Int = 200) {
        identity = HistoryIdentity(queryID: UUID(), operationID: UUID().uuidString, repositoryURL: log.repositoryURL, backendVersion: "Test")
        revisions = log.revisions
        self.pageSize = pageSize
    }

    func pause(at offset: UInt64) {
        paused.insert(offset)
    }

    func page(after cursor: HistoryCursor?) async throws -> HistoryPage {
        let offset = cursor?.offset ?? 0
        requests.append(offset)
        if paused.contains(offset) {
            return try await withCheckedThrowingContinuation {
                pending[offset] = $0
                waiters.removeValue(forKey: offset)?.resume()
            }
        }
        return result(at: offset)
    }

    private func result(at offset: UInt64) -> HistoryPage {
        let end = min(Int(offset) + pageSize, revisions.count)
        return HistoryPage(revisions: Array(revisions[Int(offset) ..< end]),
                           nextCursor: end < revisions.count ? HistoryCursor(queryID: identity.queryID, offset: UInt64(end)) : nil)
    }

    func waitForPage(_ offset: UInt64) async {
        guard pending[offset] == nil else { return }
        await withCheckedContinuation { waiters[offset] = $0 }
    }

    func finish(_ offset: UInt64, failing: Bool = false) {
        paused.remove(offset)
        let continuation = pending.removeValue(forKey: offset)
        if failing { continuation?.resume(throwing: TestFailure("Page failed")) }
        else { continuation?.resume(returning: result(at: offset)) }
    }

    func close() async {
        isClosed = true
    }
}

@MainActor
struct HistoryQueryTests {
    @Test
    func refreshAcceptsShortBackendPagesUntilHistoryEnds() async throws {
        let history = try StubHistory(log: repositoryLog("/repo", revisions: (0 ..< 5).map { revision("\($0)") }), pageSize: 2)
        let suite = "RavelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = LogSession(defaults: defaults) { _, _ in history }
        session.open(URL(fileURLWithPath: "/repo"))
        try await waitUntil { !session.isLoading }
        #expect(session.errorMessage == nil)
        #expect(session.log?.revisions.count == 5)
    }

    @Test
    func appendDoesNotDuplicateAndFailureDoesNotAdvance() async throws {
        let history = try StubHistory(log: repositoryLog("/repo", revisions: (0 ..< 405).map { revision("\($0)", parents: $0 < 404 ? ["\($0 + 1)"] : []) }))
        await history.pause(at: 200)
        let suite = "RavelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = LogSession(defaults: defaults) { _, _ in history }
        session.setHistoryPageSize(200)
        session.open(URL(fileURLWithPath: "/repo"))
        try await waitUntil { !session.isLoading }
        session.selectedRevisionID = "17"
        let prefix = try #require(session.log?.graph.rows)
        session.loadMore()
        session.loadMore()
        await history.waitForPage(200)
        await history.finish(200, failing: true)
        try await waitUntil { !session.isLoadingMore }
        #expect(session.log?.revisions.count == 200)
        #expect(session.pageErrorMessage != nil)
        session.loadMore() // automatic prefetch must not create an error loop
        #expect(await history.requests == [0, 200])
        session.loadMore(retry: true)
        try await waitUntil { !session.isLoadingMore }
        #expect(await history.requests == [0, 200, 200])
        #expect(session.log?.revisions.count == 400)
        #expect(session.selectedRevisionID == "17")
        #expect(try Array(#require(session.log?.graph.rows.prefix(200))) == prefix)
        session.loadMore()
        try await waitUntil { !session.isLoadingMore }
        #expect(session.log?.revisions.count == 405)
        #expect(session.log?.hasMore == false)
        session.loadMore()
        #expect(await history.requests == [0, 200, 200, 400])
    }

    @Test
    func oldPageCannotAppendAfterRefreshAndRefreshRetainsDepth() async throws {
        let old = try StubHistory(log: repositoryLog("/repo", revisions: (0 ..< 605).map { revision("old\($0)") }))
        let fresh = try StubHistory(log: repositoryLog("/repo", revisions: (0 ..< 610).map { revision("new\($0)") }))
        let source = QuerySequence([old, fresh])
        let suite = "RavelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = LogSession(defaults: defaults) { _, _ in await source.next() }
        session.setHistoryPageSize(200)
        session.open(URL(fileURLWithPath: "/repo"))
        try await waitUntil { !session.isLoading }
        session.loadMore()
        try await waitUntil { !session.isLoadingMore }
        #expect(session.log?.revisions.count == 400)
        await old.pause(at: 400)
        session.loadMore()
        await old.waitForPage(400)
        session.refresh()
        try await waitUntil { !session.isLoading }
        #expect(session.log?.revisions.count == 400)
        #expect(session.log?.revisions.first?.id == "new0")
        await old.finish(400)
        // A second actor request drains the continuation before checking the UI.
        try await Task.sleep(for: .milliseconds(20))
        #expect(session.log?.revisions.count == 400)
        #expect(session.log?.revisions.last?.id == "new399")
        #expect(await old.isClosed)
    }

    @Test
    func batchSizePersistsAndChangesOnlyWhenOpeningANewQuery() async throws {
        let log = try repositoryLog("/repo", revisions: (0 ..< 610).map { revision("\($0)") })
        let old = StubHistory(log: log, pageSize: 200)
        let fresh = StubHistory(log: log, pageSize: 5000)
        let source = QuerySequence([old, fresh])
        let suite = "RavelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = LogSession(defaults: defaults) { _, pageSize in await source.next(pageSize: pageSize) }
        #expect(session.historyPageSize == 1000)
        session.setHistoryPageSize(200)
        session.open(URL(fileURLWithPath: "/repo"))
        try await waitUntil { !session.isLoading }
        #expect(session.log?.revisions.count == 200)

        session.setHistoryPageSize(5000)
        #expect(LogSession(defaults: defaults).historyPageSize == 5000)
        #expect(session.log?.revisions.count == 200)
        session.loadMore()
        try await waitUntil { !session.isLoadingMore }
        #expect(session.log?.revisions.count == 400)
        #expect(await source.pageSizes == [200])

        session.refresh()
        try await waitUntil { !session.isLoading }
        #expect(await source.pageSizes == [200, 5000])
        #expect(session.log?.revisions.count == 610)
        #expect(session.log?.hasMore == false)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(condition())
    }
}

private actor QuerySequence {
    var values: [any HistoryQuery]
    private(set) var pageSizes: [Int] = []
    init(_ values: [any HistoryQuery]) {
        self.values = values
    }

    func next(pageSize: Int? = nil) -> any HistoryQuery {
        if let pageSize { pageSizes.append(pageSize) }
        return values.removeFirst()
    }
}
