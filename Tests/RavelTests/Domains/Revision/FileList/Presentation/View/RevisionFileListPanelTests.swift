//
//  RevisionFileListPanelTests.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit
@testable import Ravel
import SwiftUI
import Testing
import UserDefaultsKit

@MainActor
struct RevisionFileListPanelTests {
    @Test(arguments: [RevisionFileListMode.tree, .grouped])
    func horizontalArrowsCollapseAndReopenTheFolderWithoutReplacingThePreview(mode: RevisionFileListMode) async throws {
        let suite = "RavelFolderKeyboardTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        @Bindable var options = DiffViewOptions(store: UserDefaultsStore(defaults: defaults))
        options.fileListMode = mode
        let paths = ["App/UI/Cell.swift", "App/UI/Header.swift", "Other/Other.swift"]
        let files = paths.map { ChangedFile(path: $0, sourcePath: $0, status: .modified) }
        let session = RevisionChangesSession(loader: { _ in RevisionDiff(files: files) }, fileLoader: { _, file in
            try RevisionPatchParser.parse("@@ -0,0 +1,1 @@\n+\(file.path)\n")
        })
        defer { session.selectRevision(nil) }
        session.selectRevision(.init(repositoryURL: URL(fileURLWithPath: "/repo"), commitID: "revision", operationID: "operation"))
        try await waitUntil { session.fileDiff != nil }
        let contentID = session.fileDiff?.id
        let host = NSHostingView(rootView: RevisionFileListPanel(model: session.fileList, summary: session.summary, selection: Binding(
            get: { session.selectedFileID },
            set: { session.selectFile($0) },
        ), mode: $options.fileListMode))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let table = try #require(descendant(NSTableView.self, in: host))
        #expect(window.makeFirstResponder(table))
        let expandedRows = table.numberOfRows
        try await waitUntil { table.selectedRow == (mode == .tree ? 2 : 1) }

        try pressArrow(.left, in: table, window: window)
        try await waitUntil { session.fileList.isCollapsed("directory:App/UI", mode: mode) }
        host.layoutSubtreeIfNeeded()
        #expect(table.numberOfRows == expandedRows - 2)
        #expect(table.selectedRow >= 0)
        #expect(session.fileList.selectedDirectoryID == "directory:App/UI")
        #expect(session.selectedFileID == paths[0])
        #expect(session.fileDiff?.id == contentID)

        try pressArrow(.right, in: table, window: window)
        try await waitUntil { !session.fileList.isCollapsed("directory:App/UI", mode: mode) }
        host.layoutSubtreeIfNeeded()
        #expect(table.numberOfRows == expandedRows)
        try pressArrow(.right, in: table, window: window)
        try await waitUntil { session.fileList.selectedDirectoryID == nil }
        host.layoutSubtreeIfNeeded()
        try await waitUntil { table.selectedRow == (mode == .tree ? 2 : 1) }
        try pressArrow(.down, in: table, window: window)
        try await waitUntil { session.displayedFile?.path == paths[1] }
        #expect(table.visibleRect.intersects(table.rect(ofRow: table.selectedRow)))
    }

    @Test(arguments: RevisionFileListMode.allCases)
    func arrowKeysSelectFilesAcrossFoldersAndKeepSelectionVisible(mode: RevisionFileListMode) async throws {
        let suite = "RavelKeyboardTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        @Bindable var options = DiffViewOptions(store: UserDefaultsStore(defaults: defaults))
        options.fileListMode = mode
        let paths = (0 ..< 24).map { String(format: "Folder%02d/File%02d.swift", $0, $0) }
        let files = paths.map { ChangedFile(path: $0, sourcePath: $0, status: .modified) }
        let session = RevisionChangesSession(loader: { _ in RevisionDiff(files: files) }, fileLoader: { _, file in
            try RevisionPatchParser.parse("@@ -0,0 +1,1 @@\n+\(file.path)\n")
        })
        defer { session.selectRevision(nil) }
        session.selectRevision(.init(repositoryURL: URL(fileURLWithPath: "/repo"), commitID: "revision", operationID: "operation"))
        try await waitUntil { session.fileDiff != nil }
        let host = NSHostingView(rootView: RevisionFileListPanel(model: session.fileList, summary: session.summary, selection: Binding(
            get: { session.selectedFileID },
            set: { session.selectFile($0) },
        ), mode: $options.fileListMode))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let table = try #require(descendant(NSTableView.self, in: host))
        #expect(window.makeFirstResponder(table))
        try await waitUntil { table.selectedRow >= 0 }

        for path in paths.dropFirst() {
            try pressArrow(.down, in: table, window: window)
            try await waitUntil { session.displayedFile?.path == path }
            host.layoutSubtreeIfNeeded()
            #expect(table.selectedRow >= 0)
            #expect(table.visibleRect.intersects(table.rect(ofRow: table.selectedRow)))
        }
        try pressArrow(.down, in: table, window: window)
        #expect(session.selectedFileID == paths.last)
        try pressArrow(.up, in: table, window: window)
        try await waitUntil { session.displayedFile?.path == paths[22] }

        session.fileList.searchText = "File2"
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        try pressArrow(.up, in: table, window: window)
        try await waitUntil { session.displayedFile?.path == paths[21] }
        #expect(table.visibleRect.intersects(table.rect(ofRow: table.selectedRow)))
    }

    @Test
    func repeatedGroupingChangesKeepEveryFileAndSelection() async throws {
        let suite = "RavelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        @Bindable var options = DiffViewOptions(store: UserDefaultsStore(defaults: defaults))
        let paths = ["App/UI/Cell.swift", "App/UI/Header.swift", "App/Model.swift", "Tests/UI/CellTests.swift", "README.md"]
        let files = paths.map { RevisionFilePresentation(ChangedFile(path: $0, sourcePath: $0, status: .modified)) }
        let model = RevisionFileListViewModel()
        model.update(files: files)
        let host = NSHostingView(rootView: RevisionFileListPanel(model: model, summary: RevisionChangeSummary(files: files, statistics: nil), selection: .constant(paths[0]), mode: $options.fileListMode))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }

        for mode in [RevisionFileListMode.tree, .grouped, .list, .tree, .grouped] {
            options.fileListMode = mode
            host.layoutSubtreeIfNeeded()
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            let table = try #require(descendant(NSTableView.self, in: host))
            // Five file rows plus either four tree directories or three immediate-parent groups.
            #expect(table.numberOfRows == (mode == .tree ? 9 : mode == .grouped ? 8 : 5))
            #expect(table.selectedRow >= 0)
            let rects = (0 ..< table.numberOfRows).map { table.rect(ofRow: $0) }
            #expect(zip(rects, rects.dropFirst()).allSatisfy { $0.maxY <= $1.minY })
        }
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        for child in view.subviews {
            if let result = descendant(type, in: child) { return result }
        }
        return nil
    }

    private enum Arrow { case up, down, left, right }

    private func pressArrow(_ arrow: Arrow, in table: NSTableView, window: NSWindow) throws {
        let (key, code): (String, UInt16) = switch arrow {
        case .up: ("\u{F700}", 126)
        case .down: ("\u{F701}", 125)
        case .left: ("\u{F702}", 123)
        case .right: ("\u{F703}", 124)
        }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.numericPad, .function],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: code,
        ))
        #expect(window.firstResponder === table)
        // SwiftUI routes key-press handlers before NSTableView.keyDown(with:).
        window.sendEvent(event)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(condition(), sourceLocation: sourceLocation)
    }
}
