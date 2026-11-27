//
//  RevisionDiffTextView.swift
//  Ravel
//
//  Created by weixi on 2026/09/18.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit
import DesignSystem
import Localization

/// The text system owns layout, selection and scrolling. This view only paints diff decorations.
final class DiffReadOnlyTextView: NSTextView {
    struct VisibleRow {
        let row: DiffDisplayDocument.Row
        let frame: NSRect
        let baselineOffset: CGFloat
    }

    private(set) var contentID: UUID?
    private(set) var document: DiffDisplayDocument?
    var visibleRows: [VisibleRow] {
        rows(in: visibleRect)
    }

    private func rows(in rect: NSRect) -> [VisibleRow] {
        guard let document, let layoutManager, let textContainer, !rect.isEmpty else { return [] }
        let origin = textContainerOrigin
        // Include short rows when the reader is scrolled horizontally past their glyphs.
        let viewport = NSRect(x: 0, y: rect.minY - origin.y, width: max(1, rect.maxX - origin.x), height: rect.height)
        let glyphs = layoutManager.glyphRange(forBoundingRect: viewport, in: textContainer)
        var rows: [VisibleRow] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, range, _ in
            let offset = layoutManager.characterIndexForGlyph(at: range.location)
            if let row = document.row(atUTF16Offset: offset) {
                rows.append(VisibleRow(
                    row: row,
                    frame: rect.offsetBy(dx: origin.x, dy: origin.y),
                    baselineOffset: layoutManager.location(forGlyphAt: range.location).y,
                ))
            }
        }
        return rows
    }

    convenience init() {
        self.init(usingTextLayoutManager: false)
        isEditable = false
        isSelectable = true
        allowsUndo = false
        usesFontPanel = false
        isHorizontallyResizable = true
        isVerticallyResizable = true
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = false
        textContainer?.containerSize = maxSize
        textContainer?.lineFragmentPadding = 8
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        textColor = .labelColor
        backgroundColor = .textBackgroundColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.4
        paragraph.defaultTabInterval = 32
        paragraph.tabStops = []
        defaultParagraphStyle = paragraph
        setAccessibilityLabel(String(localized: I18n.diffAccessibilityLabel))
    }

    func setDocument(_ document: DiffDisplayDocument) {
        self.document = document
        contentID = document.id
        let string = NSMutableAttributedString(string: document.text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: defaultParagraphStyle ?? .default,
            .ligature: 0,
        ])
        for row in document.rows where row.line.kind == .hunk || row.line.kind == .metadata {
            string.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: row.range)
        }
        for range in document.commentRanges {
            string.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        }
        for row in document.rows {
            guard let emphasis = row.line.emphasis else { continue }
            let tone: ChangeTone = row.line.kind == .addition ? .addition : .deletion
            string.addAttribute(
                .backgroundColor,
                value: tone.emphasisBackground,
                range: NSRange(location: row.range.location + emphasis.location, length: emphasis.length),
            )
        }
        textStorage?.setAttributedString(string)
        setSelectedRange(NSRange(location: 0, length: 0))
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        // AppKit can draw ahead of the clip view and reuse that backing when scrolling.
        for visible in rows(in: rect) {
            guard let color = Self.background(for: visible.row.line.kind) else { continue }
            let band = NSRect(x: rect.minX, y: visible.frame.minY, width: rect.width, height: visible.frame.height)
            guard band.intersects(rect) else { continue }
            color.setFill()
            band.intersection(rect).fill()
        }
    }

    override func accessibilityLabel() -> String? {
        String(localized: I18n.diffAccessibilityLabel)
    }

    override func setAccessibilitySelectedText(_: String?) {
        // A read-only viewer permits changing the selection, but never replacing the selected text.
    }

    static func background(for kind: DiffDisplayDocument.Line.Kind) -> NSColor? {
        switch kind {
        case .addition: ChangeTone.addition.background
        case .deletion: ChangeTone.deletion.background
        case .hunk: .quaternaryLabelColor.withAlphaComponent(0.08)
        case .context, .metadata: nil
        case .spacer: .quaternaryLabelColor.withAlphaComponent(0.04)
        }
    }
}

final class DiffLineRuler: NSRulerView {
    var numberWidth: CGFloat = 36
    var showsChangeMarkers = false
    override var isFlipped: Bool {
        true
    }

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        wantsLayer = true
        clipsToBounds = true
        ruleThickness = 94
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds.intersection(rect)).addClip()
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        guard let text = scrollView?.documentView as? DiffReadOnlyTextView else { return }
        let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        for visible in text.visibleRows {
            let converted = convert(visible.frame, from: text)
            let lineRect = NSRect(x: 0, y: converted.minY, width: bounds.width, height: converted.height)
            guard lineRect.intersects(bounds) else { continue }
            if let color = DiffReadOnlyTextView.background(for: visible.row.line.kind) {
                color.setFill()
                lineRect.fill()
            }
            let line = visible.row.line
            let labelY = converted.minY + visible.baselineOffset - labelFont.ascender
            let columns: [(Int?, CGFloat)] = switch text.document?.side {
            case .before: [(line.oldNumber, numberWidth - 6)]
            case .after: [(line.newNumber, numberWidth - 6)]
            default: [(line.oldNumber, numberWidth - 6), (line.newNumber, numberWidth * 2 - 6)]
            }
            for (number, edge) in columns {
                guard let number else { continue }
                let label = String(number) as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(at: NSPoint(x: edge - size.width, y: labelY), withAttributes: attributes)
            }
            if showsChangeMarkers, line.kind == .addition || line.kind == .deletion {
                let label = (line.kind == .addition ? "+" : "−") as NSString
                label.draw(at: NSPoint(x: ruleThickness - 17, y: labelY), withAttributes: attributes)
            }
        }
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
    }
}
