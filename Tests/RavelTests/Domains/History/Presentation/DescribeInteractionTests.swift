//
//  DescribeInteractionTests.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit
import Localization
@testable import Ravel
import SwiftUI
import Testing

@MainActor
struct DescribeInteractionTests {
    @Test
    func clickedRowOwnsDraftAndSavedRevisionAcrossPages() async throws {
        let url = URL(fileURLWithPath: "/describe", isDirectory: true)
        let original = HistoryPreviewData.source
        let initial = try repositoryLog(url.path, revisions: [revision("A", workingCopy: true), original])
        let rewritten = revision("rewritten-B", change: original.changeID)
        let saved = try repositoryLog(url.path, revisions: (0 ..< 105).map { revision("other-\($0)") } + [rewritten])
        let histories = [StubHistory(log: initial), StubHistory(log: saved, pageSize: 100)]
        let loader = DescribeHistories(histories: histories)
        let suite = "DescribeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = LogSession(defaults: defaults) { _, _ in await loader.next() }
        session.setHistoryPageSize(100)
        session.open(url)
        try await settle(session)
        let log = try #require(session.log)
        let tableHost = NSHostingView(rootView: RevisionTable(
            log: log,
            selection: Binding(get: { session.selectedRevisionID }, set: { session.selectedRevisionID = $0 }),
            menuForRevision: { revision in
                let target = HistoryRevision(repositoryURL: log.repositoryURL, operationID: log.operationID, revision: revision)
                return RevisionActionMenu.describe { session.beginDescribe(target) }
            },
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 330), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = tableHost
        window.orderFront(nil)
        defer { window.close() }
        tableHost.layoutSubtreeIfNeeded()
        let table = try #require(child(NSTableView.self, of: tableHost))
        let rowPoint = NSPoint(x: 70, y: table.rect(ofRow: 1).midY)
        let click = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: table.convert(rowPoint, to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1,
        ))
        let menu = try #require(table.menu(for: click))
        let index = menu.indexOfItem(withTitle: String(localized: I18n.historyDescribe))
        try #require(index >= 0)
        menu.performActionForItem(at: index)
        let target = try #require(session.describeTarget)
        #expect(session.selectedRevisionID == "A")
        #expect(table.selectedRow == 0)
        #expect(target.revision == original)
        #expect(target.operationID == log.operationID)

        let editor = NSHostingView(rootView: RevisionDescriptionEditor(revision: target.revision, cancel: { session.describeTarget = nil }, save: { _ in }))
        window.contentView = editor
        editor.layoutSubtreeIfNeeded()
        let title = try #require(child(NSTextField.self, of: editor) { $0.isEditable })
        let body = try #require(child(NSTextView.self, of: editor) { !$0.isFieldEditor })
        #expect(title.stringValue == "Preserve selection")
        #expect(body.string == "Locate the rewritten commit.\nKeep the original selection on cancel.")

        session.describeTarget = nil
        #expect(session.selectedRevisionID == "A")
        menu.performActionForItem(at: index)
        await session.submitDescription(RevisionDescriptionDraft("New title\n\nBody\nMore"), for: target) { received, text in
            #expect(received == target)
            #expect(text.title == "New title")
            #expect(text.body == "Body\nMore")
            return HistoryWriteFeedback(commitID: rewritten.id, needsRefresh: true, message: nil)
        }
        try await settle(session)
        #expect(session.selectedRevisionID == rewritten.id)
        #expect(session.log?.revisions.count == 106)
        #expect(session.commandNotice == nil)
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/jj")))
    func repositoryMenuDescribesOldChangeWithNativeWriter() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ravel-describe-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await runJJ(["git", "init", "--colocate"], at: url)
        _ = try await runJJ(["describe", "-m", "B\n\nold first line\nold second line"], at: url)
        _ = try await runJJ(["new", "-m", "A"], at: url)
        let suite = "LiveDescribe.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = LogSession(defaults: defaults)
        session.open(url)
        try await settle(session)
        let log = try #require(session.log)
        let row = try #require(log.revisions.firstIndex { $0.summary == "B" })
        let target = log.revisions[row]
        let a = try #require(session.selectedRevision)
        #expect(a.summary == "A")
        let diff = RevisionChangesSession(loader: { _ in RevisionDiff(files: []) }, fileLoader: { _, _ in throw TestFailure("Unexpected diff") })
        let host = NSHostingView(rootView: RepositoryView(session: session, diffSession: diff).environment(DiffViewOptions()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 780), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let table = try #require(child(NSTableView.self, of: host) { $0.tableColumns.first?.identifier.rawValue == "description" })
        let click = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: table.convert(NSPoint(x: 60, y: table.rect(ofRow: row).midY), to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1,
        ))
        let menu = try #require(table.menu(for: click))
        let index = menu.indexOfItem(withTitle: String(localized: I18n.historyDescribe))
        try #require(index >= 0)
        menu.performActionForItem(at: index)
        let selected = try #require(session.describeTarget)
        #expect(selected.revision.description == "B\n\nold first line\nold second line\n")
        #expect(session.selectedRevisionID == a.id)
        session.describeTarget = nil
        #expect(session.selectedRevisionID == a.id)
        menu.performActionForItem(at: index)
        let draft = RevisionDescriptionDraft("Updated B\n\nnew first line\nnew second line")
        await session.saveDescription(draft, for: selected)
        try await settle(session)
        #expect(session.commandNotice == nil)
        let rewritten = try #require(session.selectedRevision)
        #expect(rewritten.id != target.id)
        #expect(rewritten.changeID == target.changeID)
        #expect(rewritten.description == "Updated B\n\nnew first line\nnew second line\n")
        #expect(try await runJJ(["--ignore-working-copy", "log", "-r", "@-", "--no-graph", "-T", "commit_id"], at: url) == rewritten.id)
        #expect(try await runJJ(["--ignore-working-copy", "log", "-r", "@", "--no-graph", "-T", "description.first_line()"], at: url) == "A")
        let root = try #require(session.log?.revisions.first { $0.isImmutable })
        session.beginDescribe(HistoryRevision(repositoryURL: log.repositoryURL, operationID: log.operationID, revision: root))
        #expect(session.describeTarget == nil)
        #expect(session.commandNotice?.contains("immutable()") == true)
        await session.workspace.close()
    }

    @Test(arguments: ["", "Title", "Title\n", "Title\nBody", "Title\n\nBody\n\nNext\n", "\n\nBody"])
    func unchangedFieldsPreserveExactDescription(_ text: String) {
        #expect(RevisionDescriptionDraft(text).description == text)
    }

    private func settle(_ session: LogSession) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while session.isLoading, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(!session.isLoading && session.errorMessage == nil)
    }

    private func child<T: NSView>(_ type: T.Type, of view: NSView, where matches: (T) -> Bool = { _ in true }) -> T? {
        if let result = view as? T, matches(result) { return result }
        for subview in view.subviews {
            if let result = child(type, of: subview, where: matches) { return result }
        }
        return nil
    }
}

private actor DescribeHistories {
    var histories: [StubHistory]
    init(histories: [StubHistory]) { self.histories = histories }
    func next() -> StubHistory { histories.removeFirst() }
}
