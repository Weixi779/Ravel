//
//  RevisionTable.swift
//  Ravel
//
//  Created by weixi on 2026/09/09.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit
import Localization
import SwiftUI

struct RevisionTable: NSViewRepresentable {
    let log: RepositoryLog
    @Binding var selection: String?
    var graphStyle: HistoryGraphStyle = .rounded
    var menuForRevision: ((Revision) -> NSMenu?)?
    var loadMore: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = RevisionContextTable()
        table.menuForRow = { [weak coordinator = context.coordinator] row in
            coordinator?.menu(forRow: row)
        }
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.rowHeight = 32
        table.intercellSpacing = .zero
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = false
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.backgroundColor = HistoryColors.background
        table.setAccessibilityLabel(String(localized: I18n.historyAccessibilityLabel))

        let columns: [(String, String, CGFloat, CGFloat)] = [
            ("description", String(localized: I18n.historyDescriptionColumn), 514, 280),
            ("change", String(localized: I18n.revisionChange), 96, 80),
            ("author", String(localized: I18n.revisionAuthor), 140, 85),
            ("date", String(localized: I18n.revisionDate), 150, 115),
        ]
        for (id, title, width, minimum) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = minimum
            column.resizingMask = id == "description" ? [.autoresizingMask, .userResizingMask] : [.userResizingMask]
            table.addTableColumn(column)
        }

        let scroll = RevisionScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        context.coordinator.table = table
        scroll.onViewportChange = { [weak coordinator = context.coordinator] in coordinator?.schedulePrefetch() }
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.menuForRevision = menuForRevision
        context.coordinator.update(log: log, selection: $selection, graphStyle: graphStyle, loadMore: loadMore)
        (scrollView as? RevisionScrollView)?.fitColumns()
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        (view as? RevisionScrollView)?.onViewportChange = nil
        coordinator.stopPrefetch()
        coordinator.table?.delegate = nil
        coordinator.table?.dataSource = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var table: NSTableView?
        var menuForRevision: ((Revision) -> NSMenu?)?

        func menu(forRow row: Int) -> NSMenu? {
            guard revisions.indices.contains(row) else { return nil }
            return menuForRevision?(revisions[row])
        }
        private var selection: Binding<String?>
        private var revisions: [Revision] = []
        private var graph: LogGraph?
        private var repositoryURL: URL?
        private var isApplying = false
        private var snapshotID: UUID?
        private var selectedID: String?
        private var focusedPath: Int?
        private var graphStyle: HistoryGraphStyle = .rounded
        private var loadMore: (() -> Void)?
        private var prefetchTask: Task<Void, Never>?
        private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            return formatter
        }()

        init(selection: Binding<String?>) {
            self.selection = selection
        }

        func update(log: RepositoryLog, selection: Binding<String?>, graphStyle: HistoryGraphStyle = .rounded, loadMore: @escaping () -> Void) {
            guard let table else { return }
            self.selection = selection
            self.loadMore = loadMore
            let changedSelection = selectedID != selection.wrappedValue
            selectedID = selection.wrappedValue
            self.graphStyle = graphStyle
            focusedPath = log.revisions.firstIndex(where: { $0.id == selectedID }).map { log.graph.rows[$0].color }
            isApplying = true
            defer { isApplying = false }
            let changedRepository = repositoryURL != log.repositoryURL
            if changedRepository || snapshotID != log.snapshotID || revisions.count != log.revisions.count {
                let oldCount = revisions.count
                let appending = !changedRepository && snapshotID == log.snapshotID && log.revisions.count > oldCount
                let visible = table.rows(in: table.visibleRect)
                let anchorID = revisions.indices.contains(visible.location) ? revisions[visible.location].id : nil
                let anchorOffset = table.visibleRect.minY - CGFloat(visible.location) * table.rowHeight
                revisions = log.revisions
                graph = log.graph
                repositoryURL = log.repositoryURL
                snapshotID = log.snapshotID
                if let column = table.tableColumn(withIdentifier: .init("description")) {
                    // Keep a usable title even in the widest row. Each cell still
                    // places its text after its own occupied lanes.
                    column.minWidth = max(280, HistoryGraphLayout.titleInset(after: log.graph.columnCount - 1) + 180)
                    column.width = max(column.width, column.minWidth)
                }
                if appending {
                    table.insertRows(at: IndexSet(integersIn: oldCount ..< revisions.count), withAnimation: [])
                } else {
                    table.reloadData()
                    if !changedRepository, let anchorID, let row = revisions.firstIndex(where: { $0.id == anchorID }),
                       let scroll = table.enclosingScrollView
                    {
                        scroll.contentView.scroll(to: NSPoint(x: table.visibleRect.minX, y: CGFloat(row) * table.rowHeight + anchorOffset))
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                }
            }
            if let selected = selection.wrappedValue,
               let index = revisions.firstIndex(where: { $0.id == selected })
            {
                if table.selectedRow != index {
                    table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                }
                if changedRepository || changedSelection { table.scrollRowToVisible(index) }
            } else {
                table.deselectAll(nil)
            }
            updateVisibleFocus()
            schedulePrefetch()
        }

        func schedulePrefetch() {
            prefetchTask?.cancel()
            prefetchTask = Task { [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, let table else { return }
                let visible = table.rows(in: table.visibleRect)
                guard visible.length > 0, NSMaxRange(visible) >= revisions.count - 20 else { return }
                loadMore?()
            }
        }

        func stopPrefetch() {
            prefetchTask?.cancel()
            prefetchTask = nil
            loadMore = nil
        }

        func numberOfRows(in _: NSTableView) -> Int {
            revisions.count
        }

        func tableViewSelectionDidChange(_: Notification) {
            guard !isApplying, let table else { return }
            selectedID = revisions.indices.contains(table.selectedRow) ? revisions[table.selectedRow].id : nil
            focusedPath = graph?.rows.indices.contains(table.selectedRow) == true ? graph?.rows[table.selectedRow].color : nil
            updateVisibleFocus()
            selection.wrappedValue = selectedID
        }

        private func updateVisibleFocus() {
            table?.enumerateAvailableRowViews { rowView, index in
                guard self.revisions.indices.contains(index),
                      let cell = rowView.view(atColumn: 0) as? RevisionHistoryCell else { return }
                cell.updateFocus(path: self.focusedPath, selected: self.revisions[index].id == self.selectedID, style: self.graphStyle)
            }
        }

        func tableView(_: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
            HistoryRowView()
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard revisions.indices.contains(row), let identifier = tableColumn?.identifier else { return nil }
            let revision = revisions[row]
            if identifier.rawValue == "description" {
                guard let graphRow = graph?.rows[row] else { return nil }
                let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? RevisionHistoryCell ?? RevisionHistoryCell()
                cell.identifier = identifier
                cell.configure(revision, row: graphRow)
                cell.updateFocus(path: focusedPath, selected: revision.id == selectedID, style: graphStyle)
                return cell
            }
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? TextCell ?? TextCell()
            cell.identifier = identifier
            switch identifier.rawValue {
            case "change":
                cell.label.stringValue = revision.shortChangeID
                cell.label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                cell.toolTip = String(localized: I18n.historyRevisionIdentity(revision.changeID, revision.commitID))
            case "author":
                cell.label.stringValue = revision.author
                cell.label.font = .systemFont(ofSize: 12)
                cell.toolTip = revision.email
            default:
                cell.label.stringValue = dateFormatter.string(from: revision.timestamp)
                cell.label.font = .systemFont(ofSize: 11)
                cell.toolTip = revision.timestamp.formatted()
            }
            return cell
        }

        func tableView(_: NSTableView, typeSelectStringFor _: NSTableColumn?, row: Int) -> String? {
            revisions.indices.contains(row) ? revisions[row].summary : nil
        }
    }
}

@MainActor
private final class RevisionContextTable: NSTableView {
    var menuForRow: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuForRow?(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}

@MainActor
private final class RevisionScrollView: NSScrollView {
    private var isFittingColumns = false
    var onViewportChange: (() -> Void)?

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        onViewportChange?()
    }

    override func tile() {
        super.tile()
        fitColumns()
    }

    func fitColumns() {
        guard !isFittingColumns,
              let table = documentView as? NSTableView,
              let description = table.tableColumn(withIdentifier: .init("description")),
              contentSize.width > 0 else { return }
        let fixedWidth = table.tableColumns.filter { $0 !== description }.reduce(0) { $0 + $1.width }
        let width = max(description.minWidth, contentSize.width - fixedWidth)
        guard abs(description.width - width) > 0.5 else { return }
        isFittingColumns = true
        description.width = width
        table.sizeToFit()
        isFittingColumns = false
    }
}

@MainActor
private final class TextCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.lineBreakMode = .byTruncatingTail
        label.textColor = HistoryColors.metadata
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder _: NSCoder) {
        nil
    }
}
