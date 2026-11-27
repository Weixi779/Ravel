//
//  RepositoryWriterTests.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
import Testing
@testable import Ravel

@Suite(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/jj")), .timeLimit(.minutes(1)))
struct RepositoryWriterTests {
    private func withRepository(_ exercise: (URL, RepositoryWorkspace) async throws -> Void) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ravel write \(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await runJJ(["git", "init", "--colocate"], at: url)
        _ = try await runJJ(["describe", "-m", "first"], at: url)
        _ = try await runJJ(["new", "-m", "second"], at: url)
        let workspace = RepositoryWorkspace()
        do { try await exercise(url, workspace) }
        catch { await workspace.close(); throw error }
        await workspace.close()
    }

    private func target(_ text: String, at url: URL, workspace: RepositoryWorkspace) async throws -> RevisionWriteTarget {
        let query = try await workspace.history(at: url, pageSize: 100)
        let page = try await query.page(after: nil)
        await query.close()
        let revision = try #require(page.revisions.first { $0.description.hasPrefix(text) })
        return RevisionWriteTarget(workspaceURL: query.identity.repositoryURL, operationID: query.identity.operationID, commitID: revision.commitID, changeID: revision.changeID)
    }

    @Test
    func describesSelectedAncestorAndSnapshotsDiskBeforeWriting() async throws {
        try await withRepository { url, workspace in
            let selected = try await target("first", at: url, workspace: workspace)
            try "saved".write(to: url.appendingPathComponent("notes"), atomically: true, encoding: .utf8)
            let receipt = try await workspace.describe(selected, title: "标题", body: "one\n\ntwo")
            #expect(receipt.disposition == .succeeded, "\(receipt.detail ?? "")")
            #expect(receipt.changeID == selected.changeID)
            #expect(receipt.commitID != selected.commitID)
            #expect(receipt.preparationOperationID != nil)
            #expect(receipt.mutationOperationID != nil)
            #expect(receipt.workingCopy == .completed)
            #expect(receipt.git == .completed)
            #expect(try await runJJ(["--ignore-working-copy", "log", "--no-graph", "-r", "@-", "-T", "description"], at: url) == "标题\n\none\n\ntwo\n")
            #expect(try await runJJ(["--ignore-working-copy", "file", "show", "-r", "@", "notes"], at: url) == "saved")
            await workspace.close()
            let preserved = await workspace.takeWriteReceipts()
            #expect(preserved.map(\.requestID) == [receipt.requestID])
        }
    }

    @Test(arguments: [true, false])
    func changedTargetRequiresReview(diskEdit: Bool) async throws {
        try await withRepository { url, workspace in
            let selected = try await target("second", at: url, workspace: workspace)
            if diskEdit {
                try "edit".write(to: url.appendingPathComponent("file"), atomically: true, encoding: .utf8)
            } else {
                _ = try await runJJ(["describe", "-m", "from terminal"], at: url)
            }
            let receipt = try await workspace.describe(selected, title: "overwrite", body: "")
            #expect(receipt.disposition == .staleTarget, "\(receipt.detail ?? "")")
            #expect(receipt.mutationOperationID == nil)
            #expect((receipt.preparationOperationID != nil) == diskEdit)
            #expect(receipt.currentOperationID != selected.operationID)
            let actual = try await runJJ(["--ignore-working-copy", "log", "--no-graph", "-r", "@", "-T", "description"], at: url)
            #expect(actual == (diskEdit ? "second\n" : "from terminal\n"))
        }
    }

    @Test
    func snapshotAndUndoRequireTheDisplayedOperation() async throws {
        try await withRepository { url, workspace in
            let selected = try await target("second", at: url, workspace: workspace)
            let clean = try await workspace.snapshot(at: url, operationID: selected.operationID)
            #expect(clean.currentOperationID == selected.operationID)
            #expect(clean.preparationOperationID == nil)
            try "text".write(to: url.appendingPathComponent("file"), atomically: true, encoding: .utf8)
            let snapshot = try await workspace.snapshot(at: url, operationID: selected.operationID)
            #expect(snapshot.preparationOperationID != nil)
            let before = try await workspace.operationHistory(at: url)
            _ = try await runJJ(["describe", "-m", "terminal"], at: url)
            let stale = try await workspace.undo(before)
            #expect(stale.disposition == .staleTarget)
            let latest = try await workspace.operationHistory(at: url)
            #expect(latest.undoTarget?.description.contains("describe") == true)
            let undone = try await workspace.undo(latest)
            #expect(undone.disposition == .succeeded, "\(undone.detail ?? "")")
            #expect(undone.mutationOperationID != nil)
            #expect(try await runJJ(["--ignore-working-copy", "log", "--no-graph", "-r", "@", "-T", "description"], at: url) == "second\n")
            #expect(try String(contentsOf: url.appendingPathComponent("file"), encoding: .utf8) == "text")
        }
    }

    @Test
    func reportsGitExportFailureAfterCommit() async throws {
        try await withRepository { url, workspace in
            _ = try await runJJ(["bookmark", "create", "protected-export", "-r", "@-"], at: url)
            let selected = try await target("first", at: url, workspace: workspace)
            let lock = url.appendingPathComponent(".git/refs/heads/protected-export.lock")
            try Data().write(to: lock)
            let receipt = try await workspace.describe(selected, title: "committed", body: "")
            #expect(receipt.disposition == .committedWithSyncFailure, "\(receipt.detail ?? "")")
            #expect(receipt.git == .failed)
            #expect(receipt.mutationOperationID != nil)
            #expect(try await runJJ(["--ignore-working-copy", "log", "--no-graph", "-r", "@-", "-T", "description"], at: url) == "committed\n")
        }
    }
}
