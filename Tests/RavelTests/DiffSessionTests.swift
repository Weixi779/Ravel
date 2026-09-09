// Created by weixi on 2026/09/09.

import Foundation
import Testing
@testable import Ravel

@MainActor
struct DiffSessionTests {
    @Test func obsoleteRevisionCannotPublishAfterNewSelection() async throws {
        let gate = DiffGate<RevisionDiff>()
        let session = DiffSession(loader: { try await gate.load($0.commitID) }, fileLoader: { _, _ in try FileDiff(patch: "") })
        session.selectRevision(request("old"))
        try await gate.waitForRequest("old")
        session.selectRevision(request("new"))
        try await gate.waitForRequest("new")
        await gate.finish("new", with: RevisionDiff(files: [file("new")], warning: nil))
        try await waitUntil { session.selectedFileID == "new" }
        await gate.finish("old", with: RevisionDiff(files: [file("old")], warning: nil))
        try await gate.waitForReturn("old")
        try await waitUntil { !session.isLoadingFile }
        #expect(session.diff?.files.map(\.path) == ["new"])
        #expect(session.selectedFileID == "new")
    }

    @Test func obsoleteFileCannotReplaceNewFileAndRepositorySwitchClearsContent() async throws {
        let gate = DiffGate<FileDiff>()
        let files = [file("one"), file("two")]
        let session = DiffSession(loader: { _ in RevisionDiff(files: files, warning: nil) },
                                  fileLoader: { _, file in try await gate.load(file.id) })
        session.selectRevision(request("commit"))
        try await gate.waitForRequest("one")
        session.selectFile("two")
        try await gate.waitForRequest("two")
        let newest = try FileDiff(patch: "newest\n")
        await gate.finish("two", with: newest)
        try await waitUntil { !session.isLoadingFile }
        await gate.finish("one", with: try FileDiff(patch: "obsolete\n"))
        try await gate.waitForReturn("one")
        #expect(session.fileDiff?.id == newest.id)
        session.selectRevision(nil)
        #expect(session.diff == nil && session.fileDiff == nil && session.selectedFileID == nil)
        #expect(!session.isLoading && !session.isLoadingFile)
    }

    @Test func failedFileLoadDoesNotLeavePreviousContentsVisible() async throws {
        let files = [file("good"), file("bad")]
        let session = DiffSession(loader: { _ in RevisionDiff(files: files, warning: nil) }, fileLoader: { _, file in
            if file.id == "bad" { throw JJClient.Failure.commandFailed("File unavailable") }
            return try FileDiff(patch: "content\n")
        })
        session.selectRevision(request("commit"))
        try await waitUntil { session.fileDiff != nil }
        session.selectFile("bad")
        #expect(session.fileDiff == nil)
        try await waitUntil { !session.isLoadingFile }
        #expect(session.fileErrorMessage == "File unavailable")
        #expect(session.diff?.files.count == 2)
    }

    @Test func refreshingTheSameCommitKeepsTheLoadedFile() async throws {
        let files = [file("one"), file("two")]
        let session = DiffSession(loader: { _ in RevisionDiff(files: files, warning: nil) },
                                  fileLoader: { _, _ in try FileDiff(patch: "content\n") })
        var selection = request("commit")
        session.selectRevision(selection)
        try await waitUntil { session.fileDiff != nil }
        session.selectFile("two")
        try await waitUntil { session.fileDiff != nil }
        let contentID = session.fileDiff?.id
        selection.refreshedAt = .now
        session.selectRevision(selection)
        #expect(session.fileDiff?.id == contentID)
        #expect(session.selectedFileID == "two")
        #expect(!session.isLoading && !session.isLoadingFile)
    }

    private func request(_ id: String) -> DiffSession.Request {
        .init(repositoryURL: URL(fileURLWithPath: "/repo"), commitID: id)
    }

    private func file(_ path: String) -> ChangedFile {
        .init(path: path, sourcePath: path, status: .modified)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(condition())
    }
}

private actor DiffGate<Value: Sendable> {
    private var pending: [String: CheckedContinuation<Value, any Error>] = [:]
    private var returned = Set<String>()

    func load(_ key: String) async throws -> Value {
        let value = try await withCheckedThrowingContinuation { pending[key] = $0 }
        returned.insert(key)
        return value
    }

    func finish(_ key: String, with value: Value) { pending.removeValue(forKey: key)?.resume(returning: value) }

    func waitForRequest(_ key: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while pending[key] == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(pending[key] != nil)
    }

    func waitForReturn(_ key: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !returned.contains(key) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(returned.contains(key))
    }
}
