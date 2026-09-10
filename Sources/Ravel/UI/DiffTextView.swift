// Created by weixi on 2026/09/09.

import AppKit
import SwiftUI
import Localization

struct DiffTextView: NSViewRepresentable {
    let diff: FileDiff

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        let text = NSTextView(frame: .zero)
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.isAutomaticLinkDetectionEnabled = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.allowsUndo = false
        text.isHorizontallyResizable = true
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.containerSize = text.maxSize
        text.textContainer?.widthTracksTextView = false
        text.textContainerInset = NSSize(width: 6, height: 8)
        text.setAccessibilityLabel(String(localized: I18n.diffAccessibilityLabel))
        scroll.documentView = text
        scroll.verticalRulerView = DiffLineRuler(scrollView: scroll, orientation: .verticalRuler)
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView,
              let ruler = scroll.verticalRulerView as? DiffLineRuler,
              ruler.contentID != diff.id else { return }
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 19
        paragraph.maximumLineHeight = 19
        paragraph.defaultTabInterval = 28
        paragraph.tabStops = []
        var ranges: [NSRange] = []
        for line in diff.lines {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraph,
            ]
            switch line.kind {
            case .addition:
                attributes[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.13)
            case .deletion:
                attributes[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.13)
            case .hunk:
                attributes[.foregroundColor] = NSColor.systemTeal
                attributes[.backgroundColor] = NSColor.systemTeal.withAlphaComponent(0.08)
            case .metadata: attributes[.foregroundColor] = NSColor.secondaryLabelColor
            case .context: break
            }
            let string = line.text + "\n"
            ranges.append(NSRange(location: result.length, length: (string as NSString).length))
            result.append(NSAttributedString(string: string, attributes: attributes))
        }
        text.textStorage?.setAttributedString(result)
        text.setSelectedRange(NSRange(location: 0, length: 0))
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        ruler.contentID = diff.id
        ruler.lines = diff.lines
        ruler.ranges = ranges
        ruler.needsDisplay = true
    }
}

@MainActor
private final class DiffLineRuler: NSRulerView {
    var contentID: UUID?
    var lines: [FileDiff.Line] = []
    var ranges: [NSRange] = []

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        ruleThickness = 96
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        guard let text = scrollView?.documentView as? NSTextView,
              let layout = text.layoutManager, let container = text.textContainer,
              !ranges.isEmpty else { return }
        let origin = text.textContainerOrigin
        var visible = text.visibleRect
        visible.origin.x -= origin.x
        visible.origin.y -= origin.y
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        // Binary search avoids walking all preceding lines when scrolling a large patch.
        var lower = 0
        var upper = ranges.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if NSMaxRange(ranges[middle]) <= characters.location { lower = middle + 1 }
            else { upper = middle }
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        for index in lower..<ranges.count {
            guard ranges[index].location <= NSMaxRange(characters) else { break }
            let glyph = layout.glyphIndexForCharacter(at: ranges[index].location)
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let point = convert(NSPoint(x: 0, y: fragment.minY + origin.y), from: text)
            let line = lines[index]
            for (number, edge) in [(line.oldNumber, CGFloat(43)), (line.newNumber, CGFloat(89))] {
                guard let number else { continue }
                let label = String(number) as NSString
                let width = label.size(withAttributes: attributes).width
                label.draw(at: NSPoint(x: edge - width, y: point.y + 3), withAttributes: attributes)
            }
        }
    }
}
