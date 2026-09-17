// Created by weixi on 2026/09/09.

import AppKit
import Localization
import STTextView
import SwiftUI

struct RevisionDiffView: NSViewRepresentable {
    let diff: RevisionDiffPresentation
    var sideBySide = false
    var showsChangeMarkers = false
    var findRequest = 0

    func makeNSView(context _: Context) -> RevisionDiffContainerView {
        RevisionDiffContainerView()
    }

    func updateNSView(_ view: RevisionDiffContainerView, context _: Context) {
        view.update(diff, sideBySide: sideBySide, showsChangeMarkers: showsChangeMarkers, findRequest: findRequest)
    }
}

/// Keeps text systems and synchronized scrolling inside AppKit.
final class RevisionDiffContainerView: NSView, NSSplitViewDelegate {
    private let split = NSSplitView()
    private var scrolls: [NSScrollView] = []
    private var sideBySide: Bool?
    private var isSynchronizing = false
    private var findRequest = 0
    private var needsInitialDivider = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        split.isVertical = true
        split.delegate = self
        split.dividerStyle = .thin
        split.autoresizingMask = [.width, .height]
        addSubview(split)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func layout() {
        super.layout()
        split.frame = bounds
        split.adjustSubviews()
        if needsInitialDivider, bounds.width > 0 {
            split.setPosition(bounds.width / 2, ofDividerAt: 0)
            needsInitialDivider = false
        }
    }

    func update(_ content: RevisionDiffPresentation, sideBySide: Bool, showsChangeMarkers: Bool, findRequest: Int) {
        if self.sideBySide != sideBySide {
            NotificationCenter.default.removeObserver(self)
            for column in split.arrangedSubviews {
                column.removeFromSuperview()
            }
            scrolls = (0 ..< (sideBySide ? 2 : 1)).map { _ in makeScrollView() }
            for (index, scroll) in scrolls.enumerated() {
                let title = sideBySide ? String(localized: index == 0 ? I18n.diffBefore : I18n.diffAfter) : nil
                split.addArrangedSubview(RevisionDiffColumnView(scroll: scroll, title: title))
                NotificationCenter.default.addObserver(self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
            }
            self.sideBySide = sideBySide
            needsInitialDivider = sideBySide
            needsLayout = true
            split.adjustSubviews()
        }
        let documents = sideBySide ? [content.before, content.after] : [content.unified]
        for (scroll, document) in zip(scrolls, documents) {
            guard let text = scroll.documentView as? DiffReadOnlyTextView,
                  let ruler = scroll.verticalRulerView as? DiffLineRuler else { continue }
            if text.contentID != document.id || text.document?.side != document.side {
                text.setDocument(document)
                let largest = document.rows.reduce(1) { max($0, $1.line.oldNumber ?? 0, $1.line.newNumber ?? 0) }
                ruler.numberWidth = max(36, CGFloat(String(largest).count) * 7 + 12)
                ruler.ruleThickness = ruler.numberWidth * (sideBySide ? 1 : 2) + 22
                text.scrollToBeginningOfDocument(nil)
            }
            if ruler.showsChangeMarkers != showsChangeMarkers {
                ruler.showsChangeMarkers = showsChangeMarkers
                ruler.needsDisplay = true
            }
        }
        if self.findRequest != findRequest {
            self.findRequest = findRequest
            let focused = scrolls.compactMap { $0.documentView as? DiffReadOnlyTextView }.first { $0 === window?.firstResponder }
            if let text = focused ?? scrolls.last?.documentView as? DiffReadOnlyTextView {
                window?.makeFirstResponder(text)
                let item = NSMenuItem()
                item.tag = NSTextFinder.Action.showFindInterface.rawValue
                text.performTextFinderAction(item)
            }
        }
    }

    func splitView(_: NSSplitView, canCollapseSubview _: NSView) -> Bool {
        false
    }

    func splitView(_: NSSplitView, constrainMinCoordinate _: CGFloat, ofSubviewAt _: Int) -> CGFloat {
        min(160, bounds.width / 2)
    }

    func splitView(_: NSSplitView, constrainMaxCoordinate _: CGFloat, ofSubviewAt _: Int) -> CGFloat {
        max(bounds.width - 160, bounds.width / 2)
    }

    private func makeScrollView() -> NSScrollView {
        let scroll = NSScrollView()
        scroll.wantsLayer = true
        scroll.clipsToBounds = true
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.contentView.postsBoundsChangedNotifications = true
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

    @objc
    private func scrolled(_ notification: Notification) {
        guard !isSynchronizing, scrolls.count == 2, let source = notification.object as? NSClipView else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        for scroll in scrolls where scroll.contentView !== source {
            var origin = scroll.contentView.bounds.origin
            origin.y = source.bounds.minY
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

/// Column labels share their reader's width when the divider moves.
private final class RevisionDiffColumnView: NSView {
    private let scroll: NSScrollView
    private let title: NSTextField?

    init(scroll: NSScrollView, title: String?) {
        self.scroll = scroll
        self.title = title.map { NSTextField(labelWithString: $0) }
        super.init(frame: .zero)
        addSubview(scroll)
        if let title = self.title {
            title.font = .systemFont(ofSize: 10)
            title.textColor = .secondaryLabelColor
            title.alignment = .center
            addSubview(title)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let headerHeight: CGFloat = title == nil ? 0 : 22
        scroll.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - headerHeight))
        title?.frame = NSRect(x: 0, y: bounds.height - 18, width: bounds.width, height: 14)
    }
}
