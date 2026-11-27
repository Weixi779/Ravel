//
//  HistoryCommandTests.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
@testable import Ravel
import Testing

@MainActor
struct HistoryCommandTests {
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/jj")), arguments: [false, true])
    func rebaseScopeAndLocalBookmarkLifecycle(descendants: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Graph-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await runJJ(["git", "init", "--colocate"], at: url)
        _ = try await runJJ(["describe", "-m", "source"], at: url)
        _ = try await runJJ(["new", "-m", "child"], at: url)
        _ = try await runJJ(["new", "root()", "-m", "destination"], at: url)

        let suite = "HistoryCommands.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = LogSession(defaults: defaults)
        session.open(url)
        try await settle(session)
        func row(_ name: String) throws -> HistoryRevision {
            let log = try #require(session.log)
            return try log.target(for: #require(log.revisions.first { $0.summary == name }))
        }
        let source = try row("source")
        let dest = try row("destination")
        let child = try row("child")
        let root = try #require(session.log?.revisions.first { $0.isImmutable })
        #expect(session.log?.descendantIDs(of: source.revision) == [child.revision.id])
        await session.run(.rebase(destination: dest.writeTarget, descendants: descendants), on: source)
        try await settle(session)
        let moved = try row("source")
        #expect(session.selectedRevision == moved.revision)
        #expect(moved.revision.changeID == source.revision.changeID)
        #expect(moved.revision.parentIDs == [dest.revision.id])
        #expect(try row("child").revision.parentIDs == [descendants ? moved.revision.id : root.id])

        let bookmark = "release/topic"
        await session.run(.createBookmark(name: bookmark), on: moved)
        try await settle(session)
        let marked = try row("source")
        #expect(marked.revision.localBookmarkNames == [bookmark])
        #expect(session.log?.localBookmarks.first?.commitIDs == [marked.revision.id])

        await session.run(.moveBookmark(name: bookmark, destination: try row("child").writeTarget), on: marked)
        try await settle(session)
        #expect(try row("source").revision.localBookmarkNames.isEmpty)
        let tip = try row("child")
        #expect(tip.revision.localBookmarkNames == [bookmark])
        #expect(try await runJJ(["--ignore-working-copy", "log", "-r", bookmark, "--no-graph", "-T", "commit_id"], at: url) == tip.revision.id)
        await session.run(.deleteBookmark(name: bookmark), on: tip)
        try await settle(session)
        #expect(session.log?.localBookmarks.isEmpty == true)

        let base = try row("source")
        await session.run(.newChild, on: base)
        try await settle(session)
        let new = try #require(session.selectedRevision)
        #expect(new.isWorkingCopy && new.parentIDs == [base.revision.id])
        await session.run(.edit, on: try row("child"))
        try await settle(session)
        #expect(session.selectedRevision?.summary == "child")
        #expect(session.selectedRevision?.isWorkingCopy == true)
        #expect(try await runJJ(["--ignore-working-copy", "log", "-r", "@", "--no-graph", "-T", "commit_id"], at: url) == session.selectedRevisionID)
        await session.workspace.close()
    }

    @Test
    func workingCopyAndSearchReachLaterPages() async throws {
        let url = URL(fileURLWithPath: "/paged", isDirectory: true)
        let wc = revision("working-commit", change: "zzyyxx", workingCopy: true)
        var bookmarked = HistoryPreviewData.source
        bookmarked.localBookmarkNames = ["history"]
        let revisions = (0 ..< 302).map { revision("\($0)") } + [wc, bookmarked]
        let history = try StubHistory(log: repositoryLog(url.path, revisions: revisions), pageSize: 100)
        let suite = "HistoryPaging.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = LogSession(defaults: defaults) { _, _ in history }
        session.setHistoryPageSize(100)
        session.open(url)
        try await settle(session)
        #expect(session.log?.revisions.count == 100)
        session.selectWorkingCopy()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while session.selectedRevisionID != wc.id, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(session.selectedRevisionID == wc.id)
        #expect(await history.requests == [0, 100, 200, 300])
        #expect(RevisionTargetPicker.matches(wc, query: "ZZYY"))
        #expect(RevisionTargetPicker.matches(bookmarked, query: "rewritten"))
        #expect(RevisionTargetPicker.matches(bookmarked, query: "history"))
    }

    private func settle(_ session: LogSession) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while session.isLoading, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(!session.isLoading)
        try #require(session.errorMessage == nil)
        try #require(session.commandNotice == nil)
    }
}
