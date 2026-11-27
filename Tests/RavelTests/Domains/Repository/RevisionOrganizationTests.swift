//
//  RevisionOrganizationTests.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
@testable import Ravel
import Testing
import UserDefaultsKit

@Suite(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/jj")))
nonisolated struct RevisionOrganizationTests {
    private struct Fixture {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ravel-organize-\(UUID())", isDirectory: true)

        func create() async throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            _ = try await jj(["git", "init", "--colocate"])
            _ = try await jj(["config", "set", "--repo", "revset-aliases.'immutable_heads()'", "root()"])
        }

        func jj(_ args: [String]) async throws -> String { try await runJJ(args, at: url) }

        func write(_ path: String, _ contents: String) throws {
            try Data(contents.utf8).write(to: url.appendingPathComponent(path))
        }

        func target(_ revision: String = "@") async throws -> RevisionWriteTarget {
            let ids = try await jj(["log", "-G", "-r", revision, "-T", #"commit_id ++ " " ++ change_id"#]).split(separator: " ")
            let operation = try await jj(["--ignore-working-copy", "op", "log", "-G", "-n", "1", "-T", "id"])
            return try RevisionWriteTarget(workspaceURL: url, operationID: operation, commitID: String(#require(ids.first)), changeID: String(#require(ids.last)))
        }

        func contents(_ revision: String, _ path: String) async throws -> String {
            try await jj(["--ignore-working-copy", "file", "show", "-r", revision, path])
        }
    }

    @Test(arguments: [0, 1])
    func splitHunksPreservesExactTreesAndWorkingCopy(selected: Int) async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        try await fixture.create()
        let middle = (1 ... 12).map { "unchanged \($0)\r\n" }.joined()
        let base = "old\r\n" + middle + "末尾"
        let first = "new🙂\r\nextra\r\n" + middle + "末尾"
        let second = "old\r\n" + middle + "結束"
        let final = "new🙂\r\nextra\r\n" + middle + "結束"
        try fixture.write("mixed.txt", base)
        _ = try await fixture.jj(["new", "-m", "mixed"])
        try fixture.write("mixed.txt", final)
        try fixture.write("remaining.txt", "other\n")
        let target = try await fixture.target()
        let repo = try await CodeRepository.open(fixture.url)
        let patch = try await repo.fileDiff(commitID: target.commitID, path: "mixed.txt", at: target.operationID)
        let hunks = patch.lines.compactMap(\.hunk)
        try #require(hunks.count == 2)
        let receipt = try await repo.organize(.split(first: ["mixed.txt": .hunks([hunks[selected]])]), source: target)
        try #require(receipt.disposition == .succeeded, "\(receipt.detail ?? "")")
        #expect(try await fixture.contents("@-", "mixed.txt") == (selected == 0 ? first : second))
        #expect(try await fixture.contents("@", "mixed.txt") == final)
        #expect(try await fixture.jj(["file", "list", "-r", "@-"]) == "mixed.txt\n")
        #expect(try await fixture.contents("@", "remaining.txt") == "other\n")
        #expect(try await fixture.jj(["diff", "--from", target.commitID, "--to", "@", "--summary"]).isEmpty)
        #expect(try await fixture.target().commitID == receipt.commitID)
        #expect(try await fixture.target("@-").changeID == target.changeID)
        #expect(try Data(contentsOf: fixture.url.appendingPathComponent("mixed.txt")) == Data(final.utf8))
        await repo.close()
    }

    @Test
    func selectingTheOnlyFileLeavesAnEmptyWorkingCopy() async throws {
        let f = Fixture()
        defer { try? FileManager.default.removeItem(at: f.url) }
        try await f.create()
        try f.write("single", "selected")
        let repo = try await CodeRepository.open(f.url)
        let source = try await f.target()
        let receipt = try await repo.organize(.split(first: ["single": .file]), source: source)
        try #require(receipt.disposition == .succeeded, "\(receipt.detail ?? "")")
        let graph = try await f.jj(["--ignore-working-copy", "log", "-r", "all()", "-T", #"commit_id ++ " " ++ change_id ++ " " ++ description"#])
        let at = try await f.jj(["--ignore-working-copy", "log", "-G", "-r", "@", "-T", "commit_id"])
        let mutation = try #require(receipt.mutationOperationID)
        let published = try await f.jj(["--at-op", mutation, "log", "-G", "-r", "@", "-T", "commit_id"])
        #expect(at == receipt.commitID, "\(graph) source=\(source.commitID) published=\(published) final=\(at) expected=\(receipt.commitID ?? "")")
        #expect(try await f.contents("@-", "single") == "selected")
        #expect(try await f.jj(["diff", "--summary"]).isEmpty)
        #expect(try await f.target().commitID == receipt.commitID)
        await repo.close()
    }

    @Test
    func fileSplitThenMoveToSiblingAndSquashIntoParent() async throws {
        let f = Fixture()
        defer { try? FileManager.default.removeItem(at: f.url) }
        try await f.create()
        _ = try await f.jj(["describe", "-m", "sibling"])
        let sibling = try await f.target()
        _ = try await f.jj(["new", "root()", "-m", "source"])
        try f.write("one", "first")
        try f.write("two", "second")
        try f.write("three", "third")
        let repo = try await CodeRepository.open(f.url)
        let split = try await repo.organize(.split(first: ["one": .file]), source: f.target())
        try #require(split.disposition == .succeeded, "\(split.detail ?? "")")
        #expect(try await f.jj(["file", "list", "-r", "@-"]) == "one\n")
        let move = try await repo.organize(.squash(into: f.target(sibling.changeID), paths: ["two"]), source: f.target())
        try #require(move.disposition == .succeeded, "\(move.detail ?? "")")
        #expect(try await f.contents(sibling.changeID, "two") == "second")
        #expect(try await f.jj(["file", "list", "-r", "@"]) == "one\nthree\n")
        let squash = try await repo.organize(.squash(into: f.target("@-"), paths: nil), source: f.target())
        try #require(squash.disposition == .succeeded, "\(squash.detail ?? "")")
        #expect(try await f.jj(["file", "list", "-r", "@-"]) == "one\nthree\n")
        #expect(try await f.jj(["diff", "--summary"]).isEmpty)
        #expect(try await f.target("@-").commitID == squash.commitID)
        await repo.close()
    }

    @Test
    func splittingAnAncestorKeepsTheEditedDescendantAsWorkingCopy() async throws {
        let f = Fixture()
        defer { try? FileManager.default.removeItem(at: f.url) }
        try await f.create()
        try f.write("first", "one")
        try f.write("second", "two")
        _ = try await f.jj(["new", "-m", "descendant"])
        let source = try await f.target("@-")
        let child = try await f.target()
        try f.write("local", "editor work")
        let repo = try await CodeRepository.open(f.url)
        let receipt = try await repo.organize(.split(first: ["first": .file]), source: source)
        try #require(receipt.disposition == .succeeded, "\(receipt.detail ?? "")")
        #expect(try await f.target().changeID == child.changeID)
        #expect(try await f.target("@-").commitID == receipt.commitID)
        #expect(try await f.jj(["file", "list", "-r", "@--"]) == "first\n")
        #expect(try await f.jj(["file", "list", "-r", "@-"]) == "first\nsecond\n")
        #expect(try await f.jj(["diff", "--summary"]) == "A local\n")
        #expect(try await f.contents("@", "local") == "editor work")
        await repo.close()
    }

    @Test
    func diskEditAndRewrittenDestinationRequireNewReview() async throws {
        let f = Fixture()
        defer { try? FileManager.default.removeItem(at: f.url) }
        try await f.create()
        _ = try await f.jj(["describe", "-m", "destination"])
        let dest = try await f.target()
        _ = try await f.jj(["new", "root()", "-m", "source"])
        try f.write("first", "old")
        try f.write("second", "remainder")
        let source = try await f.target()
        let repo = try await CodeRepository.open(f.url)
        try f.write("first", "externally edited")
        let split = try await repo.organize(.split(first: ["first": .file]), source: source)
        #expect(split.disposition == .staleTarget)
        #expect(split.preparationOperationID != nil)
        #expect(split.mutationOperationID == nil)
        #expect(try await f.contents("@", "first") == "externally edited")
        let fresh = try await f.target()
        _ = try await f.jj(["describe", dest.changeID, "-m", "renamed externally"])
        let move = try await repo.organize(.squash(into: dest, paths: ["first"]), source: fresh)
        #expect(move.disposition == .staleTarget)
        #expect(move.mutationOperationID == nil)
        #expect(try await f.contents("@", "second") == "remainder")
        await repo.close()
    }

    @Test
    @MainActor
    func inspectorSnapshotsBeforeReviewAndPreservesChangesOnLateEdit() async throws {
        let f = Fixture()
        defer { try? FileManager.default.removeItem(at: f.url) }
        try await f.create()
        let middle = (1 ... 12).map { "line \($0)\n" }.joined()
        try f.write("mixed", "old\n" + middle + "draft\n")
        _ = try await f.jj(["new", "-m", "settings"])
        let workspace = RepositoryWorkspace()
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let log = LogSession(store: UserDefaultsStore(defaults: defaults), workspace: workspace)
        let diff = RevisionChangesSession(loader: { try await workspace.diff($0) }, fileLoader: { try await workspace.fileDiff($0, file: $1) })
        log.open(f.url)
        while log.isLoading { await Task.yield() }
        let initial = try #require(log.selectedRevision)
        let request = try #require(log.diffRequest)
        diff.selectRevision(request, revision: initial)
        try f.write("mixed", "new\n" + middle + "ready\n")
        diff.requestOrganization(.split, source: initial, request: request)
        let review = try #require(diff.organization)
        await diff.performOrganization(review, destination: nil, log: log)
        let selection = try #require(diff.splitSelection, "\(log.commandNotice ?? "")")
        #expect(selection.source.id != initial.id)
        let ranges = try #require(diff.fileDiff?.hunks.map(\.range))
        try #require(ranges.count == 2)
        selection.setHunk(ranges[0], included: true, in: "mixed", available: ranges)
        try f.write("mixed", "updated during review\n" + middle + "ready\n")
        diff.requestOrganization(.confirmSplit, source: selection.source, request: selection.request)
        let confirm = try #require(diff.organization)
        await diff.performOrganization(confirm, destination: nil, log: log)
        while log.isLoading { await Task.yield() }
        #expect(!diff.isSelectingSplit)
        #expect(log.commandNotice != nil)
        #expect(try await f.contents("@-", "mixed") == "old\n" + middle + "draft\n")
        #expect(try await f.contents("@", "mixed") == "updated during review\n" + middle + "ready\n")
        await workspace.close()
    }

    @Test
    func binaryModeAndRenameStayWholeInFirstTree() async throws {
        let f = Fixture()
        defer { try? FileManager.default.removeItem(at: f.url) }
        try await f.create()
        try f.write("old", "renamed content")
        try f.write("script", "run")
        _ = try await f.jj(["new", "-m", "metadata"])
        try FileManager.default.moveItem(at: f.url.appendingPathComponent("old"), to: f.url.appendingPathComponent("new"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.url.appendingPathComponent("script").path)
        try Data([0, 255, 128]).write(to: f.url.appendingPathComponent("binary"))
        try f.write("rest", "left for second")
        let source = try await f.target()
        let repo = try await CodeRepository.open(f.url)
        let files = try await repo.diff(commitID: source.commitID, at: source.operationID).files
        let renamed = try #require(files.first { $0.path == "new" })
        #expect(renamed.status == .renamed)
        for file in files where ["new", "script", "binary"].contains(file.path) {
            let patch = try await repo.fileDiff(commitID: source.commitID, path: file.path, at: source.operationID)
            #expect(patch.lines.compactMap(\.hunk).isEmpty)
        }
        let receipt = try await repo.organize(.split(first: ["new": .file, "script": .file, "binary": .file]), source: source)
        try #require(receipt.disposition == .succeeded, "\(receipt.detail ?? "")")
        #expect(try await f.jj(["file", "list", "-r", "@-"]) == "binary\nnew\nscript\n")
        #expect(try await f.jj(["diff", "--summary"]) == "A rest\n")
        #expect(try await f.jj(["diff", "-r", "@-", "--git", "script"]).contains("new mode 100755"))
        #expect(try await f.jj(["diff", "--from", source.commitID, "--to", "@", "--summary"]).isEmpty)
        await repo.close()
    }

    @Test(arguments: [false, true])
    func externalToolResultIsReadBackFromTheRewrittenConflict(otherConflict: Bool) async throws {
        let f = Fixture()
        defer { try? FileManager.default.removeItem(at: f.url) }
        try await f.create()
        try f.write("conflicted", "base\n")
        if otherConflict { try f.write("other", "base\n") }
        _ = try await f.jj(["new", "-m", "left"])
        try f.write("conflicted", "left\n")
        if otherConflict { try f.write("other", "left\n") }
        let left = try await f.target()
        _ = try await f.jj(["new", "@-", "-m", "right"])
        try f.write("conflicted", "right\n")
        if otherConflict { try f.write("other", "right\n") }
        _ = try await f.jj(["new", left.commitID, "@", "-m", "merge"])
        let source = try await f.target()
        let repo = try await CodeRepository.open(f.url)
        let files = try await repo.diff(commitID: source.commitID, at: source.operationID).files
        #expect(files.filter { $0.after?.kind == .conflict }.map(\.path) == (otherConflict ? ["conflicted", "other"] : ["conflicted"]))
        _ = try await f.jj(["config", "set", "--repo", "ui.merge-editor", "ravel-fixture"])
        _ = try await f.jj(["config", "set", "--repo", "merge-tools.ravel-fixture.program", "/bin/sh"])
        _ = try await f.jj(["config", "set", "--repo", "merge-tools.ravel-fixture.merge-args", #"["-c", "cp \"$1\" \"$2\"", "resolve", "$left", "$output"]"#])
        let receipt = try await repo.organize(.resolve(path: "conflicted"), source: source)
        try #require(receipt.disposition == .succeeded, "\(receipt.detail ?? "")")
        let fresh = try await f.target()
        #expect(fresh.commitID == receipt.commitID)
        let updated = try await repo.diff(commitID: fresh.commitID, at: fresh.operationID)
        #expect(updated.files.filter { $0.after?.kind == .conflict }.map(\.path) == (otherConflict ? ["other"] : []))
        #expect(try await f.contents("@", "conflicted") == "left\n")
        await repo.close()
    }
}
