// Created by weixi on 2026/09/09.

import Foundation
import Subprocess
import Testing
@testable import Ravel

nonisolated struct JJClientTests {
    @Test func decodesEscapedDescriptionsAndStructuredParents() throws {
        let data = Data(#"""
        {"commitID":"one","changeID":"same","parentIDs":["base","other"],"description":"A \"quote\"\n中文 🚀\tend","author":"weixi","email":"weixi@example.com","timestamp":"2026-09-09T01:02:03Z","bookmarks":["feature/player@origin"],"isWorkingCopy":true,"isImmutable":false,"hasConflict":true,"isDivergent":true,"isEmpty":false}
        {"commitID":"two","changeID":"same","parentIDs":[],"description":"","author":"weixi","email":"weixi@example.com","timestamp":"2026-09-09T01:02:03Z","bookmarks":[],"isWorkingCopy":false,"isImmutable":false,"hasConflict":false,"isDivergent":true,"isEmpty":true}
        """#.utf8)
        let rows = try JJClient.decodeLog(data)
        #expect(rows.count == 2)
        #expect(rows[0].description == "A \"quote\"\n中文 🚀\tend")
        #expect(rows[0].parentIDs == ["base", "other"])
        #expect(rows[0].hasConflict && rows[0].isDivergent && rows[0].isWorkingCopy)
        #expect(rows[1].summary.isEmpty)
        #expect(rows[0].id != rows[1].id)
    }

    @Test func invalidOutputFailsInsteadOfDisplayingAPartialGraph() {
        #expect(throws: JJClient.Failure.self) { try JJClient.decodeLog(Data("not JSON\n".utf8)) }
    }

    @Test(arguments: [("jj 0.40.0", false), ("jj 0.41.0", true), ("jj 0.41.1", true), ("jj 1.0.0", true), ("unexpected", false)])
    func versionCompatibility(value: String, supported: Bool) {
        #expect(JJClient.supportsVersion(value) == supported)
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/jj")))
    func realJJLogPreservesWorkingDirectoryAndOperationHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Ravel test '中文' \(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await runJJ(["git", "init", "--colocate"], at: directory)
        _ = try await runJJ(["describe", "-m", "Ravel \"quoted\"\n第二行"], at: directory)
        _ = try await runJJ(["new", "-m", "Working change"], at: directory)
        let before = try await runJJ(["--ignore-working-copy", "--at-op=@", "op", "log", "--no-graph", "--limit", "1", "--template", "id"], at: directory)
        let file = directory.appendingPathComponent("unrecorded.txt")
        try "not snapshotted".write(to: file, atomically: true, encoding: .utf8)

        let log = try await JJClient.loadLog(at: directory, executablePath: "/opt/homebrew/bin/jj")
        let after = try await runJJ(["--ignore-working-copy", "--at-op=@", "op", "log", "--no-graph", "--limit", "1", "--template", "id"], at: directory)
        #expect(before == after)
        #expect(try String(contentsOf: file, encoding: .utf8) == "not snapshotted")
        #expect(log.revisions.filter(\.isWorkingCopy).count == 1)
        #expect(log.revisions.contains { $0.description.contains("\"quoted\"\n第二行") })
        #expect(log.revisions.first(where: \.isWorkingCopy)?.isEmpty == true)
    }

    private func runJJ(_ arguments: [String], at directory: URL) async throws -> String {
        let result = try await Subprocess.run(
            .path("/opt/homebrew/bin/jj"),
            arguments: .init(["--no-pager", "--color=never"] + arguments),
            workingDirectory: .init(directory.path),
            output: .string(limit: 1_048_576),
            error: .string(limit: 65_536)
        )
        try #require(result.terminationStatus.isSuccess, "\(result.standardError)")
        return result.standardOutput
    }
}
