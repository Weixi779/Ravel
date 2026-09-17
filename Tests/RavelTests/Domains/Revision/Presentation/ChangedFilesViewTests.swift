// Created by weixi on 2026/09/17.

import AppKit
@testable import Ravel
import SwiftUI
import Testing
import UserDefaultsKit

@MainActor
struct ChangedFilesViewTests {
    @Test
    func repeatedGroupingChangesKeepEveryFileAndSelection() async throws {
        let suite = "RavelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let options = DiffViewOptions(store: UserDefaultsStore(defaults: defaults))
        let paths = ["App/UI/Cell.swift", "App/UI/Header.swift", "App/Model.swift", "Tests/UI/CellTests.swift", "README.md"]
        let files = paths.map { ChangedFile(path: $0, sourcePath: $0, status: .modified) }
        let host = NSHostingView(rootView: ChangedFilesView(files: files, selection: .constant(paths[0]), options: options))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }

        for grouped in [false, true, false, true, false] {
            options.groupsFiles = grouped
            host.layoutSubtreeIfNeeded()
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            let table = try #require(descendant(NSTableView.self, in: host))
            // Five file rows plus either four tree directories or three immediate-parent groups.
            #expect(table.numberOfRows == (grouped ? 8 : 9))
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
}
