// Created by weixi on 2026/09/09.

import AppKit
import SwiftUI
import Localization

struct RevisionTable: NSViewRepresentable {
    let log: RepositoryLog
    @Binding var selection: String?

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
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
        table.backgroundColor = .textBackgroundColor
        table.setAccessibilityLabel(String(localized: I18n.historyAccessibilityLabel))

        let columns: [(String, String, CGFloat, CGFloat)] = [
            ("graph", String(localized: I18n.historyGraphColumn), 84, 60),
            ("description", String(localized: I18n.historyDescriptionColumn), 430, 200),
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
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(log: log, selection: $selection)
        (scrollView as? RevisionScrollView)?.fitColumns()
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        coordinator.table?.delegate = nil
        coordinator.table?.dataSource = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var table: NSTableView?
        private var selection: Binding<String?>
        private var revisions: [Revision] = []
        private var graph: LogGraph?
        private var repositoryURL: URL?
        private var isApplying = false
        private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            return formatter
        }()

        init(selection: Binding<String?>) { self.selection = selection }

        func update(log: RepositoryLog, selection: Binding<String?>) {
            guard let table else { return }
            self.selection = selection
            isApplying = true
            defer { isApplying = false }
            let changedRepository = repositoryURL != log.repositoryURL
            if changedRepository || revisions != log.revisions {
                revisions = log.revisions
                graph = log.graph
                repositoryURL = log.repositoryURL
                if let column = table.tableColumn(withIdentifier: .init("graph")) {
                    let width = max(70, CGFloat(log.graph.columnCount) * GraphCell.laneWidth + 28)
                    column.minWidth = width
                    column.width = width
                }
                table.reloadData()
            }
            if let selected = selection.wrappedValue,
               let index = revisions.firstIndex(where: { $0.id == selected }) {
                if table.selectedRow != index {
                    table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                    table.scrollRowToVisible(index)
                }
            } else {
                table.deselectAll(nil)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { revisions.count }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplying, let table else { return }
            selection.wrappedValue = revisions.indices.contains(table.selectedRow) ? revisions[table.selectedRow].id : nil
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard revisions.indices.contains(row), let identifier = tableColumn?.identifier else { return nil }
            let revision = revisions[row]
            if identifier.rawValue == "graph" {
                let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? GraphCell ?? GraphCell()
                cell.identifier = identifier
                cell.row = graph?.rows[row]
                cell.isWorkingCopy = revision.isWorkingCopy
                cell.isImmutable = revision.isImmutable
                cell.hasConflict = revision.hasConflict
                cell.toolTip = revision.isWorkingCopy ? String(localized: I18n.historyCurrentWorkingCopyHelp) : String(localized: I18n.historyCommitGraph)
                cell.setAccessibilityLabel(revision.isWorkingCopy ? String(localized: I18n.historyCurrentWorkingCopy) : revision.isImmutable ? String(localized: I18n.historyImmutableCommit) : String(localized: I18n.historyMutableCommit))
                cell.needsDisplay = true
                return cell
            }
            if identifier.rawValue == "description" {
                let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? DescriptionCell ?? DescriptionCell()
                cell.identifier = identifier
                cell.configure(revision)
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

        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            revisions.indices.contains(row) ? revisions[row].summary : nil
        }
    }
}

@MainActor
private final class RevisionScrollView: NSScrollView {
    private var isFittingColumns = false

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
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
private final class DescriptionCell: NSTableCellView {
    private let stack = NSStackView()
    private let title = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        title.lineBreakMode = .byTruncatingTail
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField = title
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ revision: Revision) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for name in revision.bookmarks.prefix(2) { stack.addArrangedSubview(BadgeView(name, color: .systemTeal)) }
        if revision.bookmarks.count > 2 { stack.addArrangedSubview(BadgeView("+\(revision.bookmarks.count - 2)", color: .secondaryLabelColor)) }
        if revision.hasConflict { stack.addArrangedSubview(BadgeView(String(localized: I18n.historyConflictBadge), color: .systemOrange)) }
        if revision.isDivergent { stack.addArrangedSubview(BadgeView(String(localized: I18n.historyDivergentBadge), color: .systemPurple)) }
        title.stringValue = revision.displaySummary
        title.font = .systemFont(ofSize: 13, weight: revision.isWorkingCopy ? .semibold : .regular)
        stack.addArrangedSubview(title)
        toolTip = revision.description
    }
}

@MainActor
private final class BadgeView: NSView {
    private let tint: NSColor
    private let label: NSTextField

    init(_ text: String, color: NSColor) {
        tint = color
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            widthAnchor.constraint(lessThanOrEqualToConstant: 160),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        toolTip = text
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        tint.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
    }
}

@MainActor
private final class GraphCell: NSView {
    static let laneWidth: CGFloat = 14
    private static let colors: [NSColor] = [.systemTeal, .systemBlue, .systemPurple, .systemOrange, .systemPink, .systemGreen]
    var row: LogGraph.Row?
    var isWorkingCopy = false
    var isImmutable = false
    var hasConflict = false
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let row, let context = NSGraphicsContext.current?.cgContext else { return }
        context.setLineWidth(1.7)
        context.setLineCap(.round)

        for segment in row.segments {
            let start = point(segment.start)
            let end = point(segment.end)
            context.setStrokeColor(Self.colors[segment.color % Self.colors.count].withAlphaComponent(0.82).cgColor)
            context.setLineDash(phase: 0, lengths: segment.isBoundary ? [2, 3] : [])
            context.beginPath()
            context.move(to: start)
            if start.x == end.x {
                context.addLine(to: end)
            } else {
                let middle = (start.y + end.y) / 2
                context.addCurve(to: end, control1: CGPoint(x: start.x, y: middle), control2: CGPoint(x: end.x, y: middle))
            }
            context.strokePath()
            if segment.isBoundary {
                context.setLineDash(phase: 0, lengths: [])
                context.move(to: CGPoint(x: end.x - 2.5, y: end.y))
                context.addLine(to: CGPoint(x: end.x + 2.5, y: end.y))
                context.strokePath()
            }
        }

        let center = CGPoint(x: 17 + CGFloat(row.nodeColumn) * Self.laneWidth, y: bounds.midY)
        let color = hasConflict ? NSColor.systemOrange : Self.colors[row.color % Self.colors.count]
        context.setLineDash(phase: 0, lengths: [])
        context.setFillColor(NSColor.textBackgroundColor.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        if isWorkingCopy {
            context.setLineWidth(1.8)
            context.strokeEllipse(in: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
            context.fillEllipse(in: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5))
        } else if isImmutable {
            context.beginPath()
            context.move(to: CGPoint(x: center.x, y: center.y - 5))
            context.addLine(to: CGPoint(x: center.x + 5, y: center.y))
            context.addLine(to: CGPoint(x: center.x, y: center.y + 5))
            context.addLine(to: CGPoint(x: center.x - 5, y: center.y))
            context.closePath()
            context.fillPath()
        } else {
            context.setLineWidth(1.8)
            context.strokeEllipse(in: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7))
        }
    }

    private func point(_ position: LogGraph.Point) -> CGPoint {
        CGPoint(x: 17 + CGFloat(position.column) * Self.laneWidth, y: CGFloat(position.fraction) * bounds.height)
    }
}
