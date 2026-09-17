// Created by weixi on 2026/09/18.

import AppKit
import DesignSystem
import Localization
import STTextView

/// The text system owns layout, selection and scrolling. This view only paints diff decorations.
final class DiffReadOnlyTextView: STTextView {
    struct VisibleRow {
        let row: DiffDisplayDocument.Row
        let frame: NSRect
    }

    private(set) var contentID: UUID?
    private(set) var document: DiffDisplayDocument?
    private(set) var visibleRows: [VisibleRow] = []
    let diffBackground = DiffBackgroundView()
    private weak var observedClipView: NSClipView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        isEditable = false
        isSelectable = true
        allowsUndo = false
        usesFontPanel = false
        allowsDocumentBackgroundColorChange = false
        isHorizontallyResizable = true
        isVerticallyResizable = true
        showsLineNumbers = false
        highlightSelectedLine = false
        isIncrementalSearchingEnabled = true
        font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textColor = .labelColor
        backgroundColor = .textBackgroundColor
        textContainer.lineFragmentPadding = 8
        let paragraph = NSMutableParagraphStyle()
        // STTextView centers glyphs using this multiplier; fixed min/max heights bypass that adjustment.
        paragraph.lineHeightMultiple = 1.4
        paragraph.defaultTabInterval = 32
        paragraph.tabStops = []
        defaultParagraphStyle = paragraph
        setAccessibilityLabel(String(localized: I18n.diffAccessibilityLabel))
        diffBackground.textView = self
        diffBackground.clipsToBounds = true
        addSubview(diffBackground, positioned: .below, relativeTo: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setDocument(_ document: DiffDisplayDocument) {
        self.document = document
        contentID = document.id
        visibleRows = []
        let string = NSMutableAttributedString(string: document.text, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: defaultParagraphStyle,
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
            string.addAttribute(.backgroundColor, value: tone.emphasisBackground,
                                range: NSRange(location: row.range.location + emphasis.location, length: emphasis.length))
        }
        attributedText = string
        textSelection = NSRange(location: 0, length: 0)
        diffBackground.needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observedClipView {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: observedClipView)
        }
        observedClipView = enclosingScrollView?.contentView
        if let observedClipView, window != nil {
            observedClipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(viewportDidScroll), name: NSView.boundsDidChangeNotification, object: observedClipView)
        }
        updateDiffDecorations()
    }

    @objc
    private func viewportDidScroll() {
        // STTextView reuses its prefetched layout during small scrolls. Decorations
        // must follow the clip view even when no new viewport layout was necessary.
        updateDiffDecorations()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func updateDiffDecorations() {
        visibleRows.removeAll(keepingCapacity: true)
        diffBackground.frame = visibleRect
        diffBackground.needsDisplay = true
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
        guard let document, let range = textLayoutManager.textViewportLayoutController.viewportRange else { return }
        let manager = textContentManager
        textLayoutManager.enumerateTextLayoutFragments(from: range.location, options: []) { fragment in
            if fragment.rangeInElement.location.compare(range.endLocation) == .orderedDescending { return false }
            let offset = manager.offset(from: manager.documentRange.location, to: fragment.rangeInElement.location)
            if let row = document.row(atUTF16Offset: offset) {
                // STTextView's internal gutter is disabled; its content starts at the view origin.
                var rect = fragment.layoutFragmentFrame
                if let lastLine = fragment.textLineFragments.last(where: { $0.characterRange.length > 0 }) {
                    rect.size.height = min(rect.height, lastLine.typographicBounds.maxY)
                }
                self.visibleRows.append(VisibleRow(row: row, frame: rect))
            }
            return true
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        backgroundColor = .textBackgroundColor
        diffBackground.needsDisplay = true
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
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

/// Keep the custom drawing surface viewport-sized, even when the document is very tall or wide.
final class DiffBackgroundView: NSView {
    weak var textView: DiffReadOnlyTextView?
    override var isFlipped: Bool {
        true
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView else { return }
        for visible in textView.visibleRows {
            guard let color = DiffReadOnlyTextView.background(for: visible.row.line.kind) else { continue }
            let converted = convert(visible.frame, from: textView)
            let rect = NSRect(x: 0, y: converted.minY, width: bounds.width, height: converted.height)
            guard rect.intersects(dirtyRect) else { continue }
            color.setFill()
            rect.fill()
        }
    }
}

struct DiffViewportPlugin: STPlugin {
    func setUp(context: any Context) {
        let view = context.textView as? DiffReadOnlyTextView
        context.events.onDidLayoutViewport { [weak view] _ in
            view?.updateDiffDecorations()
        }
        // The first viewport can already be laid out before STTextView installs its plugins on window attachment.
        view?.updateDiffDecorations()
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
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
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
            let columns: [(Int?, CGFloat)] = switch text.document?.side {
            case .before: [(line.oldNumber, numberWidth - 6)]
            case .after: [(line.newNumber, numberWidth - 6)]
            default: [(line.oldNumber, numberWidth - 6), (line.newNumber, numberWidth * 2 - 6)]
            }
            for (number, edge) in columns {
                guard let number else { continue }
                let label = String(number) as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(at: NSPoint(x: edge - size.width, y: converted.midY - size.height / 2), withAttributes: attributes)
            }
            if showsChangeMarkers, line.kind == .addition || line.kind == .deletion {
                let label = (line.kind == .addition ? "+" : "−") as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(at: NSPoint(x: ruleThickness - 17, y: converted.midY - size.height / 2), withAttributes: attributes)
            }
        }
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
    }
}
