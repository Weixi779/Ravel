// Created by weixi on 2026/09/09.

import AppKit
import Localization
import STTextView
import SwiftUI

struct DiffTextView: NSViewRepresentable {
    let diff: FileDiff
    var showsChangeMarkers = false
    var findRequest = 0

    func makeNSView(context _: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.wantsLayer = true
        scroll.clipsToBounds = true
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        let text = DiffReadOnlyTextView(frame: .zero)
        scroll.documentView = text
        let ruler = DiffLineRuler(scrollView: scroll, orientation: .verticalRuler)
        ruler.clientView = text
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        text.addPlugin(DiffViewportPlugin())
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context _: Context) {
        guard let text = scroll.documentView as? DiffReadOnlyTextView,
              let ruler = scroll.verticalRulerView as? DiffLineRuler else { return }
        if text.contentID != diff.id {
            text.setDocument(diff)
            let largestNumber = diff.lines.reduce(1) { max($0, $1.oldNumber ?? 0, $1.newNumber ?? 0) }
            ruler.numberWidth = max(36, CGFloat(String(largestNumber).count) * 7 + 12)
            ruler.ruleThickness = ruler.numberWidth * 2 + 22
            text.scrollToBeginningOfDocument(nil)
        }
        if ruler.showsChangeMarkers != showsChangeMarkers {
            ruler.showsChangeMarkers = showsChangeMarkers
            ruler.needsDisplay = true
        }
        if text.findRequest != findRequest {
            text.findRequest = findRequest
            scroll.window?.makeFirstResponder(text)
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            text.performTextFinderAction(item)
        }
    }
}

/// The text system owns layout, selection and scrolling. This view only paints diff decorations.
final class DiffReadOnlyTextView: STTextView {
    struct VisibleRow {
        let row: DiffDisplayDocument.Row
        let frame: NSRect
    }

    private(set) var contentID: UUID?
    private(set) var document: DiffDisplayDocument?
    private(set) var visibleRows: [VisibleRow] = []
    var findRequest = 0
    private let diffBackground = DiffBackgroundView()

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
        textColor = .textColor
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

    func setDocument(_ diff: FileDiff) {
        let document = DiffDisplayDocument(diff)
        self.document = document
        contentID = diff.id
        visibleRows = []
        let string = NSMutableAttributedString(string: document.text, attributes: [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: defaultParagraphStyle,
            .ligature: 0,
        ])
        for row in document.rows where row.line.kind == .hunk || row.line.kind == .metadata {
            string.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: row.range)
        }
        attributedText = string
        textSelection = NSRange(location: 0, length: 0)
        diffBackground.needsDisplay = true
    }

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

    static func background(for kind: FileDiff.Line.Kind) -> NSColor? {
        switch kind {
        case .addition: .systemGreen.withAlphaComponent(0.13)
        case .deletion: .systemRed.withAlphaComponent(0.13)
        case .hunk: .quaternaryLabelColor.withAlphaComponent(0.08)
        case .context, .metadata: nil
        }
    }
}

/// Keep the custom drawing surface viewport-sized, even when the document is very tall or wide.
private final class DiffBackgroundView: NSView {
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

private struct DiffViewportPlugin: STPlugin {
    func setUp(context: any Context) {
        let view = context.textView as? DiffReadOnlyTextView
        context.events.onDidLayoutViewport { [weak view] _ in
            view?.updateDiffDecorations()
        }
        // The first viewport can already be laid out before STTextView installs its plugins on window attachment.
        view?.updateDiffDecorations()
    }
}

private final class DiffLineRuler: NSRulerView {
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
            for (number, edge) in [(line.oldNumber, numberWidth - 6), (line.newNumber, numberWidth * 2 - 6)] {
                guard let number else { continue }
                let label = String(number) as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(at: NSPoint(x: edge - size.width, y: converted.midY - size.height / 2), withAttributes: attributes)
            }
            if showsChangeMarkers, line.kind == .addition || line.kind == .deletion {
                let label = (line.kind == .addition ? "+" : "−") as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(at: NSPoint(x: numberWidth * 2 + 3, y: converted.midY - size.height / 2), withAttributes: attributes)
            }
        }
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
    }
}
