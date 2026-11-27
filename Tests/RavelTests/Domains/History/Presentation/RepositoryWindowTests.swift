//
//  RepositoryWindowTests.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit
@testable import Ravel
import Testing

@MainActor
struct RepositoryWindowTests {
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/jj")))
    func visibleUnfocusedWindowTracksDiskAndOperationsThenSnapshotsOnFocus() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ravel-window-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await runJJ(["git", "init", "--colocate"], at: url)
        try "ignored/\n".write(to: url.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        _ = try await runJJ(["describe", "-m", "Initial"], at: url)
        let suite = "RavelWindow-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = LogSession(defaults: defaults)
        session.open(url)
        try await wait { session.log != nil }
        let initial = try #require(session.log)
        let window = makeWindow(x: 20)
        let view = RepositoryWindowObservationView()
        window.contentView = view
        var split = false
        view.observe(session: session, isSelectingSplit: { split })
        defer {
            view.stop()
            window.close()
        }
        window.orderFrontRegardless()
        window.setTestFocus(false)
        try await wait { window.occlusionState.contains(.visible) && !window.isKeyWindow }

        let ignored = url.appendingPathComponent("ignored", isDirectory: true)
        try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: true)
        try Data([0]).write(to: ignored.appendingPathComponent("temporary"))
        #expect(try await !session.workspace.hasDiskChanges(at: initial.repositoryURL))
        let changed = url.appendingPathComponent("new-file.txt")
        try "visible but not focused".write(to: changed, atomically: true, encoding: .utf8)
        try await wait { session.hasDiskChanges }
        #expect(session.log?.snapshotID == initial.snapshotID)
        #expect(try await session.workspace.operationHeads(at: initial.repositoryURL) == [initial.operationID])

        split = true
        window.setTestFocus(true)
        try await wait { window.isKeyWindow }
        try await Task.sleep(for: .milliseconds(350))
        #expect(try await session.workspace.operationHeads(at: initial.repositoryURL) == [initial.operationID])
        window.setTestFocus(false)
        try await wait { !window.isKeyWindow }
        split = false
        window.setTestFocus(true)
        try await wait { session.log?.operationID != initial.operationID && !session.hasDiskChanges && !session.isLoading }
        let snapshotted = try #require(session.log)
        let wc = try #require(snapshotted.revisions.first { $0.isWorkingCopy })
        let files = try await session.workspace.diff(RevisionDiffRequest(repositoryURL: snapshotted.repositoryURL, commitID: wc.id, operationID: snapshotted.operationID))
        #expect(files.files.contains { $0.path == "new-file.txt" })
        window.setTestFocus(false)
        try await wait { !window.isKeyWindow }
        _ = try await runJJ(["describe", "-m", "Terminal update"], at: url)
        try await wait { session.selectedRevision?.summary == "Terminal update" }
        let terminal = try #require(session.log)
        window.orderOut(nil)
        try await wait { !window.occlusionState.contains(.visible) }
        _ = try await runJJ(["describe", "-m", "While hidden"], at: url)
        try await Task.sleep(for: .milliseconds(350))
        #expect(session.log?.snapshotID == terminal.snapshotID)
        window.orderFrontRegardless()
        try await wait { session.selectedRevision?.summary == "While hidden" }
        let clean = try #require(session.log)
        await session.reconcileWindow(checkDisk: true, focus: true) { true }
        #expect(session.log?.snapshotID == clean.snapshotID)
        #expect(try await session.workspace.operationHeads(at: clean.repositoryURL) == [clean.operationID])
        await session.workspace.close()
    }

    private func makeWindow(x: CGFloat) -> ObservedTestWindow {
        let window = ObservedTestWindow(contentRect: NSRect(x: x, y: 80, width: 250, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func wait(sourceLocation: SourceLocation = #_sourceLocation, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition(), sourceLocation: sourceLocation)
    }
}

/// Changing the globally frontmost application from an app-hosted test depends
/// on the Window Server session. Drive its key notification deterministically.
private final class ObservedTestWindow: NSWindow {
    private var focused = false
    override var isKeyWindow: Bool { focused }

    func setTestFocus(_ value: Bool) {
        focused = value
        NotificationCenter.default.post(name: value ? NSWindow.didBecomeKeyNotification : NSWindow.didResignKeyNotification, object: self)
    }
}
