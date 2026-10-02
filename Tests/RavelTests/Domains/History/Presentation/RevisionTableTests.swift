//
//  RevisionTableTests.swift
//  Ravel
//
//  Created by weixi on 2026/09/18.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit
import Observation
@testable import Ravel
import SwiftUI
import Testing

@MainActor
struct RevisionTableTests {
    @Test(arguments: [HistoryGraphStyle.rounded, .curved], [false, true])
    func historyKeepsGraphTextAndSelectionTogether(style: HistoryGraphStyle, dark: Bool) async throws {
        let revisions = Self.revisions
        let fixture = try Fixture(log: repositoryLog("/history-render-test", revisions: Array(revisions.prefix(12))), style: style)
        let host = NSHostingView(rootView: Host(fixture: fixture))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 540), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        await settle(host)
        let table = try #require(descendant(NSTableView.self, in: host))
        #expect(table.tableColumns.map(\.identifier.rawValue) == ["description", "change", "author", "date"])
        #expect(table.selectedRow == 0)
        let initialGraph = fixture.log.graph
        let initialTextX = try titleX(row: 0, in: table)

        // Select a side path with the native table, then propagate the binding.
        table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        await settle(host)
        #expect(fixture.selection == revisions[2].id)
        let focusedTitle = try cell(row: 2, in: table).textField
        let contextTitle = try cell(row: 1, in: table).textField
        #expect(focusedTitle?.textColor == HistoryColors.title)
        #expect(contextTitle?.textColor == HistoryColors.contextTitle)
        #expect(try titleX(row: 0, in: table) == initialTextX)

        #expect(window.makeFirstResponder(table))
        let down = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{F701}",
            charactersIgnoringModifiers: "\u{F701}",
            isARepeat: false,
            keyCode: 125,
        ))
        table.keyDown(with: down)
        await settle(host)
        #expect(fixture.selection == revisions[3].id)
        #expect(try cell(row: 3, in: table).textField?.textColor == HistoryColors.title)
        #expect(try cell(row: 2, in: table).textField?.textColor == HistoryColors.contextTitle)
        fixture.selection = revisions[2].id
        await settle(host)

        // Append through the same snapshot, exactly as pagination does.
        var graph = initialGraph
        try graph.append(Array(revisions.suffix(from: 12)))
        var appended = fixture.log
        appended.revisions = revisions
        appended.graph = graph
        appended.hasMore = false
        fixture.log = appended
        await settle(host)
        #expect(table.numberOfRows == revisions.count)
        #expect(table.selectedRow == 2)
        #expect(Array(fixture.log.graph.rows.prefix(12)) == initialGraph.rows)
        for (index, revision) in revisions.enumerated() {
            let view = try cell(row: index, in: table)
            #expect(view.textField?.stringValue == revision.displaySummary)
            #expect(try titleX(row: index, in: table) >= HistoryGraphLayout.titleInset(after: graph.rows[index].occupiedColumn))
        }
        #expect(try titleX(row: revisions.count - 1, in: table) < titleX(row: 5, in: table))

        window.setContentSize(NSSize(width: 720, height: 540))
        await settle(host)
        let compactTitle = try #require(cell(row: 4, in: table).textField)
        #expect(compactTitle.frame.width >= 100)
        window.setContentSize(NSSize(width: 1120, height: 540))

        // A programmatic selection and an appearance/style update keep the same rows.
        fixture.selection = revisions[0].id
        fixture.style = style == .rounded ? .curved : .rounded
        await settle(host)
        #expect(table.selectedRow == 0)
        #expect(fixture.log.revisions.map(\.id) == revisions.map(\.id))
        fixture.style = style
        await settle(host)
        if let directory = ProcessInfo.processInfo.environment["RAVEL_RENDER_OUTPUT"],
           let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        {
            host.cacheDisplay(in: host.bounds, to: image)
            try image.representation(using: .png, properties: [:])?.write(
                to: URL(fileURLWithPath: directory)
                    .appendingPathComponent("history-\(style.rawValue)-\(dark ? "dark" : "light").png"),
            )
        }
        fixture.selection = nil
        await settle(host)
        #expect(table.selectedRow == -1)
        #expect(try cell(row: 1, in: table).textField?.textColor == HistoryColors.title)
    }

    @Test(arguments: [HistoryGraphStyle.rounded, .curved])
    func turnsStayInsideTheirRowAndClearTheText(style: HistoryGraphStyle) throws {
        let graph = try LogGraph(revisions: Self.revisions)
        for row in graph.rows {
            for segment in row.segments {
                let path = HistoryGraphLayout.path(for: segment, height: 32, style: style)
                let bounds = path.boundingBoxOfPath
                #expect(bounds.minY >= 0)
                #expect(bounds.maxY <= 32)
                #expect(bounds.maxX + 7 < HistoryGraphLayout.titleInset(after: row.occupiedColumn))
                #expect(path.currentPoint == HistoryGraphLayout.point(segment.end, height: 32))
            }
        }
    }

    private func settle(_ host: NSView) async {
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(30))
        host.layoutSubtreeIfNeeded()
        host.window?.displayIfNeeded()
    }

    private func cell(row: Int, in table: NSTableView) throws -> RevisionHistoryCell {
        try #require(table.view(atColumn: 0, row: row, makeIfNecessary: true) as? RevisionHistoryCell)
    }

    private func titleX(row: Int, in table: NSTableView) throws -> CGFloat {
        let cell = try cell(row: row, in: table)
        cell.layoutSubtreeIfNeeded()
        let title = try #require(cell.textField)
        return cell.convert(title.alignmentRect(forFrame: title.frame), from: title.superview).minX
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        for child in view.subviews {
            if let result = descendant(type, in: child) { return result }
        }
        return nil
    }

    private static var revisions: [Revision] {
        let data: [(String, [String], String, [String])] = [
            ("search", ["search-merge"], "Keep search results visible while switching revisions", ["search"]),
            ("window", ["window-base"], "Restore the window's reading position", ["window-state"]),
            ("parser", ["parser-base"], "Parse multi-parent history without reordering", ["parser"]),
            ("docs", ["docs-base"], "Document the repository reader lifecycle", ["docs"]),
            ("theme", ["theme-base"], "Keep each path's hue in the background", ["appearance"]),
            ("search-merge", ["search-base", "parser-base"], "Merge the parser changes into search", []),
            ("parser-base", ["common"], "Preserve parent lanes between history pages", []),
            ("docs-base", ["common"], "Add examples for pagination and cancellation", []),
            ("theme-base", ["common"], "Define light and dark history color roles", []),
            ("search-base", ["common"], "Focus the path and its commit titles together", []),
            ("window-base", ["common"], "Retain selection when refreshing the repository", []),
            ("common", ["older"], "Unify graph and description into one reading surface", ["main"]),
            ("older", ["root"], "Read revisions in their original topological order", []),
            ("root", [], "Create the repository", []),
        ]
        return data.enumerated().map { index, item in
            Revision(
                commitID: item.0,
                changeID: "change-\(index)",
                parentIDs: item.1,
                description: item.2,
                author: "weixi",
                email: "weixi@example.com",
                timestamp: Date(timeIntervalSince1970: 1_789_000_000 - Double(index * 900)),
                bookmarks: item.3,
                isWorkingCopy: index == 0,
                isImmutable: index >= 11,
                hasConflict: index == 4,
                isDivergent: false,
                isEmpty: false,
            )
        }
    }

    @Observable
    fileprivate final class Fixture {
        var log: RepositoryLog
        var selection: String? = "search"
        var style: HistoryGraphStyle

        init(log: RepositoryLog, style: HistoryGraphStyle) {
            self.log = log
            self.style = style
        }
    }

    private struct Host: View {
        @Bindable var fixture: Fixture

        var body: some View {
            RevisionTable(log: fixture.log, selection: $fixture.selection, graphStyle: fixture.style)
        }
    }
}
