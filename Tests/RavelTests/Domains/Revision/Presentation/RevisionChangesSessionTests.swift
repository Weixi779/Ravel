//
//  RevisionChangesSessionTests.swift
//  Ravel
//
//  Created by weixi on 2026/09/09.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
@testable import Ravel
import Testing

@MainActor
struct RevisionChangesSessionTests {
    @Test
    func obsoleteRevisionCannotPublishAfterNewSelection() async throws {
        let gate = DiffGate<RevisionDiff>()
        let session = RevisionChangesSession(loader: { try await gate.load($0.commitID) }, fileLoader: { _, _ in try RevisionPatchParser.parse("") })
        session.selectRevision(request("old"))
        try await gate.waitForRequest("old")
        session.selectRevision(request("new"))
        try await gate.waitForRequest("new")
        await gate.finish("new", with: RevisionDiff(files: [file("new")]))
        try await waitUntil { session.selectedFileID == "new" }
        await gate.finish("old", with: RevisionDiff(files: [file("old")]))
        try await gate.waitForReturn("old")
        try await waitUntil { !session.isLoadingFile }
        #expect(session.diff?.files.map(\.path) == ["new"])
        #expect(session.selectedFileID == "new")
    }

    @Test
    func obsoleteFileCannotReplaceNewFileAndRepositorySwitchClearsContent() async throws {
        let gate = DiffGate<FileDiff>()
        let files = [file("initial"), file("one"), file("two")]
        let session = RevisionChangesSession(
            loader: { _ in RevisionDiff(files: files) },
            fileLoader: { _, file in
                if file.id == "initial" { return try RevisionPatchParser.parse("initial\n") }
                return try await gate.load(file.id)
            },
        )
        session.selectRevision(request("commit"))
        try await waitUntil { session.fileDiff != nil }
        session.selectFile("one")
        try await gate.waitForRequest("one")
        session.selectFile("two")
        try await gate.waitForRequest("two")
        let newest = try RevisionPatchParser.parse("newest\n")
        await gate.finish("two", with: newest)
        try await waitUntil { !session.isLoadingFile }
        try await gate.finish("one", with: RevisionPatchParser.parse("obsolete\n"))
        try await gate.waitForReturn("one")
        #expect(session.fileDiff?.id == newest.id)
        session.selectRevision(nil)
        #expect(session.diff == nil && session.fileDiff == nil && session.selectedFileID == nil)
        #expect(!session.isLoading && !session.isLoadingFile)
    }

    @Test
    func failedFileLoadDoesNotLeavePreviousContentsVisible() async throws {
        let files = [file("good"), file("bad")]
        let session = RevisionChangesSession(loader: { _ in RevisionDiff(files: files) }, fileLoader: { _, file in
            if file.id == "bad" { throw TestFailure("File unavailable") }
            return try RevisionPatchParser.parse("content\n")
        })
        session.selectRevision(request("commit"))
        try await waitUntil { session.fileDiff != nil }
        session.selectFile("bad")
        #expect(session.fileDiff != nil)
        try await waitUntil { !session.isLoadingFile }
        #expect(session.fileErrorMessage == "File unavailable")
        #expect(session.diff?.files.count == 2)
    }

    @Test
    func refreshingTheSameCommitKeepsTheLoadedFile() async throws {
        let files = [file("one"), file("two")]
        let session = RevisionChangesSession(
            loader: { _ in RevisionDiff(files: files) },
            fileLoader: { _, _ in try RevisionPatchParser.parse("content\n") },
        )
        var selection = request("commit")
        session.selectRevision(selection)
        try await waitUntil { session.fileDiff != nil }
        session.selectFile("two")
        try await waitUntil { !session.isLoadingFile }
        let contentID = session.fileDiff?.id
        selection.refreshedAt = .now
        session.selectRevision(selection)
        #expect(session.fileDiff?.id == contentID)
        #expect(session.selectedFileID == "two")
        #expect(!session.isLoading && !session.isLoadingFile)
    }

    @Test
    func refreshingTheSameCommitRestartsPendingStatisticsWithoutClearingItsReader() async throws {
        let stats = DiffGate<RevisionDiffStatistics>()
        let files = [file("A")]
        let session = RevisionChangesSession(loader: { _ in RevisionDiff(files: files) }, fileLoader: { _, _ in
            try RevisionPatchParser.parse("A content\n")
        }, statisticsLoader: { request in try await stats.load(request.operationID) })
        var selection = request("revision")
        session.selectRevision(selection)
        try await stats.waitForRequest("operation")
        try await waitUntil { session.fileDiff != nil }
        let contentID = session.fileDiff?.id
        selection = RevisionDiffRequest(repositoryURL: selection.repositoryURL, commitID: selection.commitID, operationID: "refreshed")
        session.selectRevision(selection)
        try await stats.waitForRequest("refreshed")
        #expect(session.fileDiff?.id == contentID)
        #expect(!session.isLoading)
        await stats.finish("refreshed", with: RevisionDiffStatistics(files: [:], additions: 3, deletions: 1, binaryFiles: 0))
        try await waitUntil { session.summary.additions == 3 }
        await stats.finish("operation", with: RevisionDiffStatistics(files: [:], additions: 99, deletions: 99, binaryFiles: 0))
        try await stats.waitForReturn("operation")
        #expect(session.summary.additions == 3)
        session.selectRevision(nil)
    }

    @Test
    func switchingPreservesACompleteSnapshotAndCachedReturnSkipsLoading() async throws {
        let gate = DiffGate<FileDiff>()
        let session = RevisionChangesSession(loader: { request in
            RevisionDiff(files: [ChangedFile(path: request.commitID, sourcePath: request.commitID, status: .modified)])
        }, fileLoader: { request, _ in try await gate.load(request.commitID) }, loadingDelay: .milliseconds(30))
        session.selectRevision(request("A"))
        try await gate.waitForRequest("A")
        #expect(!session.showsRevisionProgress)
        try await gate.finish("A", with: RevisionPatchParser.parse("A content\n"))
        try await waitUntil { !session.isLoading }
        let firstID = session.fileDiff?.id
        session.selectRevision(request("B"))
        try await gate.waitForRequest("B")
        #expect(session.displayedFile?.path == "A")
        #expect(session.displayedTitle == "A")
        #expect(session.fileDiff?.id == firstID)
        try await waitUntil { session.showsRevisionProgress }
        try await gate.finish("B", with: RevisionPatchParser.parse("B content\n"))
        try await waitUntil { !session.isLoading }
        #expect(session.displayedFile?.path == "B")
        #expect(session.displayedTitle == "B")
        #expect(!session.showsRevisionProgress)
        session.selectRevision(request("A"))
        #expect(session.displayedFile?.path == "A")
        #expect(session.fileDiff?.id == firstID)
        #expect(!session.isLoading && !session.showsRevisionProgress)
        session.selectRevision(nil)
    }

    @Test
    func fileLoadingKeepsItsOwnHeaderAndStatisticsDoNotBlockText() async throws {
        let gate = DiffGate<FileDiff>()
        let stats = DiffGate<RevisionDiffStatistics>()
        let files = [file("A"), file("B")]
        let session = RevisionChangesSession(loader: { _ in RevisionDiff(files: files) }, fileLoader: { _, file in
            if file.path == "A" { return try RevisionPatchParser.parse("A content\n") }
            return try await gate.load(file.path)
        }, statisticsLoader: { request in try await stats.load(request.commitID) }, loadingDelay: .milliseconds(30))
        session.selectRevision(request("revision"))
        try await stats.waitForRequest("revision")
        try await waitUntil { session.fileDiff != nil }
        #expect(session.summary.additions == nil)
        session.selectFile("B")
        try await gate.waitForRequest("B")
        #expect(session.selectedFileID == "B")
        #expect(session.displayedFile?.path == "A")
        #expect(session.fileDiff?.unified.text == "A content\n")
        #expect(!session.showsFileProgress)
        try await waitUntil { session.showsFileProgress }
        await stats.finish("revision", with: RevisionDiffStatistics(files: ["B": .init(additions: 2, deletions: 1, bytesDelta: 8)], additions: 2, deletions: 1, binaryFiles: 0))
        try await waitUntil { session.summary.additions == 2 }
        #expect(session.displayedFile?.path == "A")
        try await gate.finish("B", with: RevisionPatchParser.parse("B content\n"))
        try await waitUntil { !session.isLoadingFile }
        #expect(session.displayedFile?.statistics?.additions == 2)
        #expect(session.fileDiff?.unified.text == "B content\n")
        #expect(!session.showsFileProgress)
        session.selectFile("A")
        #expect(session.displayedFile?.path == "A")
        #expect(!session.isLoadingFile)
        session.selectRevision(nil)
    }

    @Test
    func returningToDisplayedFileCancelsAPendingOtherFile() async throws {
        let gate = DiffGate<FileDiff>()
        let files = [file("A"), file("B")]
        let session = RevisionChangesSession(loader: { _ in RevisionDiff(files: files) }, fileLoader: { _, file in
            if file.path == "A" { return try RevisionPatchParser.parse("A content\n") }
            return try await gate.load("B")
        }, loadingDelay: .milliseconds(30))
        session.selectRevision(request("revision"))
        try await waitUntil { session.fileDiff != nil }
        session.selectFile("B")
        try await gate.waitForRequest("B")
        session.selectFile("A")
        try await gate.finish("B", with: RevisionPatchParser.parse("B content\n"))
        try await gate.waitForReturn("B")
        try await Task.sleep(for: .milliseconds(60))
        #expect(session.displayedFile?.path == "A")
        #expect(session.selectedFileID == "A")
        #expect(!session.isLoadingFile && !session.showsFileProgress)
        session.selectRevision(nil)
    }

    private func request(_ id: String) -> RevisionDiffRequest {
        .init(repositoryURL: URL(fileURLWithPath: "/repo"), commitID: id, operationID: "operation")
    }

    private func file(_ path: String) -> ChangedFile {
        .init(path: path, sourcePath: path, status: .modified)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
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

    func finish(_ key: String, with value: Value) {
        pending.removeValue(forKey: key)?.resume(returning: value)
    }

    func waitForRequest(_ key: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while pending[key] == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(pending[key] != nil)
    }

    func waitForReturn(_ key: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !returned.contains(key), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(returned.contains(key))
    }
}
