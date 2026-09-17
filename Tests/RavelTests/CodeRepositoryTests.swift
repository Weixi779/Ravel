// Created by weixi on 2026/09/09.

import Foundation
import Testing
@testable import Ravel

nonisolated struct CodeRepositoryTests {
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/jj")), arguments: [1, 1000, 5000])
    func rustHistoryMatchesCLIAndPreservesWorkingDirectoryAndOperations(pageSize: Int) async throws {
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
        let query = try await repository.history(pageSize: pageSize)
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
        let diff = try await repository.diff(commitID: workingCopy.id, at: before)
        #expect(diff.files.isEmpty)
        await repository.close()
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/jj")), .timeLimit(.minutes(1)))
    func userInitiatedReadsRecoverFromCancellationAndAllowConcurrentClose() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Ravel bridge \(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await runJJ(["git", "init", "--colocate"], at: directory)

        // Exercise the actual generated async bridge at the priority in the warning.
        try await Task(priority: .userInitiated) {
            let repository = try await CodeRepository.open(directory)
            do {
                for _ in 0..<8 {
                    let query = try await repository.history(pageSize: 1000)
                    await Task {
                        withUnsafeCurrentTask { $0?.cancel() }
                        await #expect(throws: CancellationError.self) { try await query.page(after: nil) }
                    }.value
                    let page = try await query.page(after: nil)
                    #expect(page.revisions.count == 2) // Working copy and root.
                    #expect(page.nextCursor == nil)
                    let workingCopy = try #require(page.revisions.first { $0.isWorkingCopy })
                    let diff = try await repository.diff(commitID: workingCopy.id, at: query.identity.operationID)
                    #expect(diff.files.isEmpty)
                    async let firstClose: Void = query.close()
                    async let secondClose: Void = query.close()
                    _ = await (firstClose, secondClose)
                    await #expect(throws: (any Error).self) { try await query.page(after: nil) }
                }
            } catch {
                await repository.close()
                throw error
            }
            async let firstClose: Void = repository.close()
            async let secondClose: Void = repository.close()
            _ = await (firstClose, secondClose)
            await #expect(throws: (any Error).self) { try await repository.history(pageSize: 1000) }
        }.value
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
