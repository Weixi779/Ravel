// Created by weixi on 2026/09/09.

import Foundation
import Subprocess
import Testing
@testable import Ravel

nonisolated struct DiffTests {
    @Test func unifiedHunksKeepIndependentLineNumbersAndLiteralPrefixes() throws {
        let patch = """
        diff --git a/file b/file
        --- a/file
        +++ b/file
        @@ -2,3 +2,3 @@ function
         keep
        ---looks like a header
        +++also a header
         last
        @@ -20 +20,2 @@
        -before
        +after
        +extra
        \\ No newline at end of file
        """
        let diff = try FileDiff(patch: patch)
        let removed = diff.lines.filter { $0.kind == .deletion }
        let added = diff.lines.filter { $0.kind == .addition }
        #expect(removed.map(\.oldNumber) == [3, 20])
        #expect(added.map(\.newNumber) == [3, 20, 21])
        #expect(removed[0].text == "---looks like a header")
        #expect(added.allSatisfy { $0.oldNumber == nil })
        #expect(diff.lines.last?.kind == .metadata)
    }

    @Test func zeroLengthRangesAndCRLFRemainReadable() throws {
        let added = try FileDiff(patch: "@@ -0,0 +1,2 @@\n+你好 🧶\r\n+second\r\n")
        #expect(added.lines.map(\.newNumber) == [nil, 1, 2])
        #expect(added.lines[1].text == "+你好 🧶\r")
        let removed = try FileDiff(patch: "@@ -1,1 +0,0 @@\n-gone\n")
        #expect(removed.lines.last?.oldNumber == 1)
        #expect(removed.lines.last?.newNumber == nil)
    }

    @Test(arguments: ["@@ -1,2 +1,1 @@\n-old\n+new\n", "@@ -x +1 @@\n+a\n", "@@ -1 +1 @@\ninvalid\n"])
    func incompleteOrMalformedHunksAreRejected(patch: String) {
        #expect(throws: FileDiff.Failure.self) { try FileDiff(patch: patch) }
    }

    @Test func binaryAndMetadataOnlyChangesHaveNoInventedLineNumbers() throws {
        let binary = try FileDiff(patch: "diff --git a/a b/a\nBinary files a/a and b/a differ\n")
        #expect(binary.isBinary)
        let mode = try FileDiff(patch: "diff --git a/a b/a\nold mode 100644\nnew mode 100755\n")
        #expect(!mode.isBinary)
        #expect(mode.lines.allSatisfy { $0.oldNumber == nil && $0.newNumber == nil })
        #expect(try FileDiff(patch: "").lines.isEmpty)
    }

    @Test func oversizedPatchesFailExplicitly() {
        #expect(throws: FileDiff.Failure.self) {
            try FileDiff(patch: String(repeating: "a", count: FileDiff.byteLimit))
        }
        #expect(throws: FileDiff.Failure.self) {
            try FileDiff(patch: String(repeating: "line\n", count: FileDiff.lineLimit + 1))
        }
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/jj")))
    func realJJDiffHandlesFileStatusesExactPathsAndReadOnlyAccess() async throws {
        let repo = try temporaryRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        _ = try await jj(["git", "init", "--colocate"], at: repo)
        try write("before\n", to: "modified.txt", in: repo)
        try write("remove\n", to: "removed.txt", in: repo)
        try write("rename\n", to: "old.txt", in: repo)
        try write("#!/bin/sh\n", to: "executable", in: repo)
        _ = try await jj(["new", "-m", "File changes"], at: repo)
        try write("after\n", to: "modified.txt", in: repo)
        try FileManager.default.removeItem(at: repo.appendingPathComponent("removed.txt"))
        try FileManager.default.moveItem(at: repo.appendingPathComponent("old.txt"), to: repo.appendingPathComponent("renamed.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.appendingPathComponent("executable").path)
        let unusual = "新 'quote' \"(a)*\\\t\nfile.txt"
        try write("only this file\n", to: unusual, in: repo)
        try write("", to: "empty.txt", in: repo)
        try Data([0, 1, 2, 255]).write(to: repo.appendingPathComponent("binary.dat"))
        let commit = try await jj(["log", "-r", "@", "-G", "-T", "commit_id"], at: repo)
        _ = try await jj(["config", "set", "--repo", "ui.diff-formatter", "false"], at: repo)
        let before = try await operation(in: repo)
        try write("unrecorded", to: "unrecorded.txt", in: repo)
        let request = DiffSession.Request(repositoryURL: repo, commitID: commit, executablePath: "/opt/homebrew/bin/jj")
        let diff = try await JJClient.loadDiff(request)
        #expect(diff.files.count == 7)
        #expect(diff.files.first { $0.path == "modified.txt" }?.status == .modified)
        #expect(diff.files.first { $0.path == "removed.txt" }?.status == .removed)
        let rename = try #require(diff.files.first { $0.path == "renamed.txt" })
        #expect(rename.status == .renamed)
        #expect(rename.sourcePath == "old.txt")
        let renamePatch = try await JJClient.loadFileDiff(request, file: rename)
        #expect(renamePatch.lines.contains { $0.text == "rename from old.txt" })

        let special = try #require(diff.files.first { $0.path == unusual })
        let specialPatch = try await JJClient.loadFileDiff(request, file: special)
        #expect(specialPatch.lines.filter { $0.kind == .addition }.map(\.text) == ["+only this file"])
        let binary = try #require(diff.files.first { $0.path == "binary.dat" })
        #expect(try await JJClient.loadFileDiff(request, file: binary).isBinary)
        let executable = try #require(diff.files.first { $0.path == "executable" })
        #expect(try await JJClient.loadFileDiff(request, file: executable).lines.contains { $0.text == "new mode 100755" })
        #expect(try await operation(in: repo) == before)
        #expect(try String(contentsOf: repo.appendingPathComponent("unrecorded.txt"), encoding: .utf8) == "unrecorded")
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/jj")))
    func oversizedCLIOutputUsesThePreviewLimitMessage() async throws {
        let repo = try temporaryRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        _ = try await jj(["git", "init", "--colocate"], at: repo)
        _ = try await jj(["config", "set", "--repo", "snapshot.max-new-file-size", "10485760"], at: repo)
        try write(String(repeating: "large line\n", count: 220_000), to: "large.txt", in: repo)
        let commit = try await jj(["log", "-r", "@", "-G", "-T", "commit_id"], at: repo)
        let request = DiffSession.Request(repositoryURL: repo, commitID: commit, executablePath: "/opt/homebrew/bin/jj")
        let file = ChangedFile(path: "large.txt", sourcePath: "large.txt", status: .added)
        await #expect(throws: FileDiff.Failure.self) {
            try await JJClient.loadFileDiff(request, file: file)
        }
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/jj")))
    func mergeDiffComparesAgainstMergedParents() async throws {
        let repo = try temporaryRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        _ = try await jj(["git", "init", "--colocate"], at: repo)
        try write("base\n", to: "base.txt", in: repo)
        let base = try await jj(["log", "-r", "@", "-G", "-T", "commit_id"], at: repo)
        _ = try await jj(["new", base], at: repo)
        try write("left\n", to: "left.txt", in: repo)
        let left = try await jj(["log", "-r", "@", "-G", "-T", "commit_id"], at: repo)
        _ = try await jj(["new", base], at: repo)
        try write("right\n", to: "right.txt", in: repo)
        let right = try await jj(["log", "-r", "@", "-G", "-T", "commit_id"], at: repo)
        _ = try await jj(["new", left, right], at: repo)
        var commit = try await jj(["log", "-r", "@", "-G", "-T", "commit_id"], at: repo)
        var request = DiffSession.Request(repositoryURL: repo, commitID: commit, executablePath: "/opt/homebrew/bin/jj")
        #expect(try await JJClient.loadDiff(request).files.isEmpty)
        try write("merge adjustment\n", to: "merged.txt", in: repo)
        commit = try await jj(["log", "-r", "@", "-G", "-T", "commit_id"], at: repo)
        request = DiffSession.Request(repositoryURL: repo, commitID: commit, executablePath: "/opt/homebrew/bin/jj")
        let diff = try await JJClient.loadDiff(request)
        #expect(diff.files.map(\.path) == ["merged.txt"])
        let file = try #require(diff.files.first)
        #expect(try await JJClient.loadFileDiff(request, file: file).lines.filter { $0.kind == .addition }.map(\.text) == ["+merge adjustment"])
    }

    private func temporaryRepository() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Ravel diff '中文' \(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func write(_ text: String, to path: String, in repo: URL) throws {
        try text.write(to: repo.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    private func operation(in repo: URL) async throws -> String {
        try await jj(["--ignore-working-copy", "--at-op=@", "op", "log", "-G", "-n", "1", "-T", "id"], at: repo)
    }

    private func jj(_ arguments: [String], at repo: URL) async throws -> String {
        let result = try await Subprocess.run(.path("/opt/homebrew/bin/jj"),
            arguments: .init(["--no-pager", "--color=never"] + arguments),
            workingDirectory: .init(repo.path), output: .string(limit: 1_048_576), error: .string(limit: 65_536))
        try #require(result.terminationStatus.isSuccess, "\(result.standardError)")
        return result.standardOutput
    }
}
