//
//  RevisionHistoryCell.swift
//  Ravel
//
//  Created by weixi on 2026/09/18.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import AppKit
import Localization

enum HistoryGraphLayout {
    static let laneWidth: CGFloat = 18
    static let leading: CGFloat = 17

    static func titleInset(after column: Int) -> CGFloat {
        leading + CGFloat(column) * laneWidth + 14
    }

    static func point(_ point: LogGraph.Point, height: CGFloat) -> CGPoint {
        CGPoint(x: leading + CGFloat(point.column) * laneWidth, y: CGFloat(point.fraction) * height)
    }

    static func path(for segment: LogGraph.Segment, height: CGFloat, style: HistoryGraphStyle) -> CGPath {
        let start = point(segment.start, height: height)
        let end = point(segment.end, height: height)
        let path = CGMutablePath()
        path.move(to: start)
        if start.x == end.x {
            path.addLine(to: end)
        } else {
            let middle = (start.y + end.y) / 2
            switch style {
            case .curved:
                path.addCurve(to: end, control1: CGPoint(x: start.x, y: middle), control2: CGPoint(x: end.x, y: middle))
            case .rounded:
                let direction: CGFloat = end.x > start.x ? 1 : -1
                let radius = min(6, abs(end.x - start.x) / 2, (end.y - start.y) / 2)
                path.addLine(to: CGPoint(x: start.x, y: middle - radius))
                path.addQuadCurve(to: CGPoint(x: start.x + direction * radius, y: middle), control: CGPoint(x: start.x, y: middle))
                path.addLine(to: CGPoint(x: end.x - direction * radius, y: middle))
                path.addQuadCurve(to: CGPoint(x: end.x, y: middle + radius), control: CGPoint(x: end.x, y: middle))
                path.addLine(to: end)
            }
        }
        return path
    }
}

@MainActor
final class RevisionHistoryCell: NSTableCellView {
    private let graph = HistoryGraphView()
    private let stack = NSStackView()
    private let title = NSTextField(labelWithString: "")
    private var textInset: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        graph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(graph)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        textInset = stack.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            textInset,
            graph.leadingAnchor.constraint(equalTo: leadingAnchor),
            graph.trailingAnchor.constraint(equalTo: stack.leadingAnchor),
            graph.topAnchor.constraint(equalTo: topAnchor),
            graph.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        title.lineBreakMode = .byTruncatingTail
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let readableTitle = title.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)
        readableTitle.priority = .defaultHigh
        readableTitle.isActive = true
        textField = title
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func configure(_ revision: Revision, row: LogGraph.Row) {
        graph.row = row
        graph.isWorkingCopy = revision.isWorkingCopy
        graph.isImmutable = revision.isImmutable
        graph.hasConflict = revision.hasConflict
        graph.setAccessibilityElement(true)
        graph.setAccessibilityRole(.image)
        graph.setAccessibilityLabel(revision.isWorkingCopy ? String(localized: I18n.historyCurrentWorkingCopy) : revision.isImmutable ? String(localized: I18n.historyImmutableCommit) : String(localized: I18n.historyMutableCommit))
        textInset.constant = HistoryGraphLayout.titleInset(after: row.occupiedColumn)
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for name in revision.bookmarks.prefix(2) {
            stack.addArrangedSubview(HistoryBadgeView(name, color: HistoryColors.metadata))
        }
        if revision.bookmarks.count > 2 {
            stack.addArrangedSubview(HistoryBadgeView("+\(revision.bookmarks.count - 2)", color: HistoryColors.metadata))
        }
        if revision.hasConflict {
            stack.addArrangedSubview(HistoryBadgeView(String(localized: I18n.historyConflictBadge), color: HistoryColors.conflict))
        }
        if revision.isDivergent {
            stack.addArrangedSubview(HistoryBadgeView(String(localized: I18n.historyDivergentBadge), color: HistoryColors.divergent))
        }
        title.stringValue = revision.displaySummary
        title.font = .systemFont(ofSize: 13, weight: revision.isWorkingCopy ? .semibold : .regular)
        stack.addArrangedSubview(title)
        toolTip = ([revision.description] + revision.bookmarks).joined(separator: "\n")
    }

    func updateFocus(path: Int?, selected: Bool, style: HistoryGraphStyle) {
        graph.focusedPath = path
        graph.isSelectedRevision = selected
        graph.style = style
        let focused = selected || path == nil || path.map { graph.row?.isOnPath($0) == true } == true
        title.textColor = focused ? HistoryColors.title : HistoryColors.contextTitle
        graph.needsDisplay = true
    }

    func invalidateSelection() {
        graph.needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        graph.needsDisplay = true
    }
}

@MainActor
final class HistoryRowView: NSTableRowView {
    /// The selected title and path keep their theme colors on the subtle row fill.
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        .normal
    }

    override var isEmphasized: Bool {
        didSet {
            needsDisplay = true
            subviews.compactMap { $0 as? RevisionHistoryCell }.forEach { $0.invalidateSelection() }
        }
    }

    override func drawSelection(in _: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        (isEmphasized ? HistoryColors.selection : HistoryColors.inactiveSelection).setFill()
        bounds.fill()
    }
}

@MainActor
private final class HistoryGraphView: NSView {
    var row: LogGraph.Row?
    var focusedPath: Int?
    var isSelectedRevision = false
    var style: HistoryGraphStyle = .rounded
    var isWorkingCopy = false
    var isImmutable = false
    var hasConflict = false

    override var isFlipped: Bool {
        true
    }

    override func draw(_: NSRect) {
        guard let row, let context = NSGraphicsContext.current?.cgContext else { return }
        context.setLineWidth(1.8)
        context.setLineCap(.round)
        // Draw the focused path last, so crossings do not interrupt it.
        for focused in [false, true] {
            for segment in row.segments {
                let isFocused = focusedPath == nil || segment.color == focusedPath
                guard isFocused == focused else { continue }
                context.setStrokeColor(HistoryColors.path(segment.color, focused: isFocused).cgColor)
                context.addPath(HistoryGraphLayout.path(for: segment, height: bounds.height, style: style))
                context.strokePath()
            }
        }

        let center = HistoryGraphLayout.point(.init(column: row.nodeColumn, fraction: 0.5), height: bounds.height)
        let focused = isSelectedRevision || focusedPath == nil || focusedPath.map { row.isOnPath($0) } == true
        let color = hasConflict ? HistoryColors.conflict : HistoryColors.path(row.color, focused: focused)
        let rowView = superview?.superview as? NSTableRowView
        let background = isSelectedRevision
            ? (rowView?.isEmphasized == true ? HistoryColors.selection : HistoryColors.inactiveSelection)
            : HistoryColors.background
        let radius: CGFloat = isSelectedRevision ? 7 : 5
        context.setFillColor(background.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        if isSelectedRevision {
            context.setLineWidth(1)
            context.strokeEllipse(in: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14))
        }
        context.setLineWidth(1.8)
        if isWorkingCopy {
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
            context.strokeEllipse(in: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7))
        }
    }
}

@MainActor
private final class HistoryBadgeView: NSView {
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

    required init?(coder _: NSCoder) {
        nil
    }

    override func draw(_: NSRect) {
        tint.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
    }
}
