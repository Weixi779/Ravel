// Created by weixi on 2026/09/09.

import Foundation
import Subprocess
import Testing
@testable import Ravel

nonisolated struct JJClientTests {
    @Test(arguments: [("jj 0.40.0", false), ("jj 0.41.0", true), ("jj 0.41.1", true), ("jj 1.0.0", true), ("unexpected", false)])
    func versionCompatibility(value: String, supported: Bool) {
        #expect(JJClient.supportsVersion(value) == supported)
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/jj")))
    func rustHistoryMatchesCLIAndPreservesWorkingDirectoryAndOperations() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Ravel test '中文' \(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await runJJ(["git", "init", "--colocate"], at: directory)
        _ = try await runJJ(["describe", "-m", "Ravel \"quoted\"\n第二行"], at: directory)
        _ = try await runJJ(["new", "-m", "Working change"], at: directory)
        let before = try await runJJ(["--ignore-working-copy", "--at-op=@", "op", "log", "--no-graph", "--limit", "1", "--template", "id"], at: directory)
        let file = directory.appendingPathComponent("unrecorded.txt")
        try "not snapshotted".write(to: file, atomically: true, encoding: .utf8)

        let repository = try await CodeRepository.open(directory)
        let query = try await repository.history(pageSize: 1)
        var records: [Revision] = []
        var cursor: HistoryCursor?
        repeat {
            let page = try await query.page(after: cursor)
            records.append(contentsOf: page.revisions)
            cursor = page.nextCursor
        } while cursor != nil
        let reference = try await runJJ(["--ignore-working-copy", "--at-op=@", "log", "-r", "all()", "--no-graph", "-T", Self.logTemplate], at: directory)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let expected = try reference.utf8.split(separator: 0x0A).map { try decoder.decode(CLIRevisionReference.self, from: Data($0)) }
        #expect(records.map(\.id) == expected.map(\.commitID))
        for (actual, expected) in zip(records, expected) {
            #expect(actual.changeID == expected.changeID)
            #expect(actual.parentIDs == expected.parentIDs)
            #expect(actual.description == expected.description)
            #expect(actual.author == expected.author)
            #expect(actual.email == expected.email)
            #expect(actual.bookmarks == expected.bookmarks)
            #expect(actual.isImmutable == expected.isImmutable)
            #expect(actual.isWorkingCopy == expected.isWorkingCopy)
            #expect(actual.hasConflict == expected.hasConflict)
            #expect(actual.isDivergent == expected.isDivergent)
            #expect(actual.isEmpty == expected.isEmpty)
            #expect(abs(actual.timestamp.timeIntervalSince(expected.timestamp)) < 1)
        }
        await #expect(throws: (any Error).self) {
            try await query.page(after: HistoryCursor(queryID: UUID(), offset: 0))
        }
        await repository.close()
        let after = try await runJJ(["--ignore-working-copy", "--at-op=@", "op", "log", "--no-graph", "--limit", "1", "--template", "id"], at: directory)
        #expect(before == after)
        #expect(try String(contentsOf: file, encoding: .utf8) == "not snapshotted")
        #expect(records.filter(\.isWorkingCopy).count == 1)
        #expect(records.contains { $0.description.contains("\"quoted\"\n第二行") })
        #expect(records.first(where: \.isWorkingCopy)?.isEmpty == true)

        // Concurrent new operations must not change this inspector's read view.
        _ = try await runJJ(["describe", "--at-op", before, "-m", "Concurrent one"], at: directory)
        _ = try await runJJ(["describe", "--at-op", before, "-m", "Concurrent two"], at: directory)
        let workingCopy = try #require(records.first { $0.isWorkingCopy })
        let diff = try await JJClient.loadDiff(RevisionDiffRequest(repositoryURL: directory,
            commitID: workingCopy.id, executablePath: "/opt/homebrew/bin/jj", operationID: before))
        #expect(diff.files.isEmpty)
    }

    static let logTemplate = #"""
    '{' ++
    '"commitID":' ++ json(commit_id) ++ ',' ++
    '"changeID":' ++ json(change_id) ++ ',' ++
    '"parentIDs":' ++ json(parents.map(|p| p.commit_id())) ++ ',' ++
    '"description":' ++ json(description) ++ ',' ++
    '"author":' ++ json(author.name()) ++ ',' ++
    '"email":' ++ json(stringify(author.email())) ++ ',' ++
    '"timestamp":' ++ json(committer.timestamp().utc().format("%Y-%m-%dT%H:%M:%SZ")) ++ ',' ++
    '"bookmarks":' ++ json(bookmarks.map(|b| stringify(b))) ++ ',' ++
    '"isWorkingCopy":' ++ json(current_working_copy) ++ ',' ++
    '"isImmutable":' ++ json(immutable) ++ ',' ++
    '"hasConflict":' ++ json(conflict) ++ ',' ++
    '"isDivergent":' ++ json(divergent) ++ ',' ++
    '"isEmpty":' ++ json(empty) ++ "}\n"
    """#


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

// CLI JSON is an independent test oracle, not the application's domain format.
nonisolated private struct CLIRevisionReference: Decodable {
    let commitID: String
    let changeID: String
    let parentIDs: [String]
    let description: String
    let author: String
    let email: String
    let timestamp: Date
    let bookmarks: [String]
    let isWorkingCopy: Bool
    let isImmutable: Bool
    let hasConflict: Bool
    let isDivergent: Bool
    let isEmpty: Bool
}
