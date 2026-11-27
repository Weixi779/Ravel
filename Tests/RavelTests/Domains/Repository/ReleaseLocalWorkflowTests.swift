//
//  ReleaseLocalWorkflowTests.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
@testable import Ravel
import Testing

@Suite(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/jj")), .timeLimit(.minutes(1)))
@MainActor
struct ReleaseLocalWorkflowTests {
    private struct Checkout {
        let url: URL
        let path = "Settings.swift"
        let middle = (1 ... 24).map { "// line \($0)\n" }.joined()

        func contents(_ timeout: Int, _ title: String) -> String {
            "let timeout = \(timeout)\n" + middle + "let title = \"\(title)\"\n"
        }

        func write(_ value: String) throws {
            try value.write(to: url.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }

        func jj(_ args: [String]) async throws -> String {
            try await runJJ(args, at: url)
        }

        func file(at revision: String) async throws -> String {
            try await jj(["--ignore-working-copy", "file", "show", "-r", revision, path])
        }

        func revision(_ revset: String) async throws -> String {
            try await jj(["--ignore-working-copy", "log", "-r", revset, "--no-graph", "-T", "commit_id"])
        }

        func create() async throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            _ = try await jj(["git", "init", "--colocate"])
            try write(contents(5, "Draft"))
            _ = try await jj(["describe", "-m", "Base"])
            let base = try await revision("@")
            _ = try await jj(["new", "-m", "Destination"])
            try Data("destination".utf8).write(to: url.appendingPathComponent("destination.txt"))
            _ = try await jj(["new", base, "-m", "Collision"])
            try write(contents(60, "Collision"))
            _ = try await jj(["new", base, "-m", "Mixed"])
            // A deterministic external merge editor. The test exercises the same tool launch,
            // output capture and return path as a configured interactive editor.
            _ = try await jj(["config", "set", "--repo", "ui.merge-editor", "release-test"])
            let resolution = url.appendingPathComponent(".jj/release-test-resolution")
            try contents(60, "Ready").write(to: resolution, atomically: true, encoding: .utf8)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            let args = try encoder.encode([resolution.path, "$output"])
            _ = try await jj(["config", "set", "--repo", "merge-tools.release-test.program", "/bin/cp"])
            _ = try await jj(["config", "set", "--repo", "merge-tools.release-test.merge-args", String(decoding: args, as: UTF8.self)])
        }
    }

    private func settle(_ log: LogSession) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(6))
        while log.isLoading, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(8))
        }
        try #require(!log.isLoading && log.errorMessage == nil, "\(log.errorMessage ?? "")")
    }

    @Test
    func twoHunksThroughRebaseBookmarkUndoAndConflictReturn() async throws {
        let checkout = Checkout(url: FileManager.default.temporaryDirectory.appendingPathComponent("Ravel local release \(UUID())", isDirectory: true))
        defer { try? FileManager.default.removeItem(at: checkout.url) }
        try await checkout.create()
        let suite = "ReleaseWorkflow.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let log = LogSession(defaults: defaults)
        let workspace = log.workspace
        let diff = RevisionChangesSession(loader: { try await workspace.diff($0) }, fileLoader: { try await workspace.fileDiff($0, file: $1) })
        log.open(checkout.url)
        try await settle(log)
        func row(_ summary: String) throws -> HistoryRevision {
            let graph = try #require(log.log)
            return try graph.target(for: #require(graph.revisions.first { $0.summary == summary }, "Missing \(summary), available \(graph.revisions.map(\.summary)), notice \(log.commandNotice ?? "")"))
        }
        let initial = try row("Mixed")
        let finalContents = checkout.contents(15, "Ready")
        try checkout.write(finalContents)
        let snapshot = try await workspace.snapshot(at: checkout.url, operationID: initial.operationID)
        try #require(snapshot.disposition == .succeeded)
        log.refresh()
        try await settle(log)
        #expect(try await checkout.file(at: "@") == finalContents)

        let mixed = try row("Mixed")
        let request = try #require(log.diffRequest)
        diff.selectRevision(request, revision: mixed.revision)
        diff.requestOrganization(.split, source: mixed.revision, request: request)
        await diff.performOrganization(try #require(diff.organization), destination: nil, log: log)
        let selection = try #require(diff.splitSelection, "\(log.commandNotice ?? "")")
        let hunks = try #require(diff.fileDiff?.hunks.map(\.range))
        try #require(hunks.count == 2)
        selection.setHunk(hunks[0], included: true, in: checkout.path, available: hunks)
        diff.requestOrganization(.confirmSplit, source: selection.source, request: selection.request)
        await diff.performOrganization(try #require(diff.organization), destination: nil, log: log)
        try await settle(log)
        #expect(try await checkout.file(at: "@-") == checkout.contents(15, "Draft"))
        #expect(try await checkout.file(at: "@") == finalContents)
        let upper = try #require(log.log?.revisions.first { $0.isWorkingCopy })
        let lower = try #require(log.log?.revisions.first { $0.id == upper.parentIDs.first })
        log.beginDescribe(try #require(log.log).target(for: lower))
        await log.saveDescription(RevisionDescriptionDraft("Set timeout\n\nUse 15 seconds."), for: try #require(log.describeTarget))
        try await settle(log)
        let updatedUpper = try #require(log.log?.revisions.first { $0.isWorkingCopy })
        log.beginDescribe(try #require(log.log).target(for: updatedUpper))
        await log.saveDescription(RevisionDescriptionDraft("Update title\n\nShow Ready."), for: try #require(log.describeTarget))
        try await settle(log)
        let dest = try row("Destination")
        await log.run(.rebase(destination: dest.writeTarget, descendants: true), on: try row("Set timeout"))
        try await settle(log)
        let moved = try row("Set timeout")
        let top = try row("Update title")
        #expect(moved.revision.parentIDs == [dest.revision.id])
        #expect(top.revision.parentIDs == [moved.revision.id])
        #expect(top.revision.isWorkingCopy)
        #expect(try await checkout.jj(["--ignore-working-copy", "file", "show", "-r", "@", "destination.txt"]) == "destination")
        await log.run(.createBookmark(name: "deliver"), on: top)
        try await settle(log)
        await log.run(.moveBookmark(name: "deliver", destination: try row("Set timeout").writeTarget), on: try row("Update title"))
        try await settle(log)
        #expect(try await checkout.revision("deliver") == moved.revision.id)
        let confirmation = try await workspace.operationHistory(at: checkout.url)
        try #require(confirmation.undoTarget?.description.contains("move bookmark deliver") == true)
        let undone = try await workspace.undo(confirmation)
        try #require(undone.disposition == .succeeded, "\(undone.detail ?? "")")
        log.refresh()
        try await settle(log)
        #expect(try await checkout.revision("deliver") == top.revision.id)
        #expect(try await checkout.revision("@") == top.revision.id)

        let collision = try row("Collision")
        await log.run(.rebase(destination: collision.writeTarget, descendants: false), on: try row("Update title"))
        try await settle(log)
        let conflicted = try row("Update title")
        try #require(conflicted.revision.hasConflict && conflicted.revision.isWorkingCopy)
        #expect(conflicted.revision.parentIDs == [collision.revision.id])
        let conflictRequest = try #require(log.diffRequest)
        let paths = try await workspace.diff(conflictRequest).files.filter { $0.after?.kind == .conflict }.map(\.path)
        #expect(paths == [checkout.path])
        diff.selectRevision(conflictRequest, revision: conflicted.revision)
        diff.requestOrganization(.resolveFile(checkout.path), source: conflicted.revision, request: conflictRequest)
        await diff.performOrganization(try #require(diff.organization), destination: nil, log: log)
        try await settle(log)
        let resolved = try row("Update title")
        #expect(!resolved.revision.hasConflict && resolved.revision.isWorkingCopy)
        #expect(resolved.revision.parentIDs == [collision.revision.id])
        #expect(try await checkout.revision("deliver") == resolved.revision.id)
        #expect(try await checkout.revision("@") == resolved.revision.id)
        #expect(try row("Set timeout").revision.parentIDs == [dest.revision.id])
        let disk = try String(contentsOf: checkout.url.appendingPathComponent(checkout.path), encoding: .utf8)
        #expect(try await checkout.file(at: "@") == disk)
        #expect(disk == checkout.contents(60, "Ready"))
        #expect(try await workspace.diff(#require(log.diffRequest)).files.allSatisfy { $0.after?.kind != .conflict })
        await workspace.close()
    }
}
