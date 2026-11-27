//
//  RevisionInspectorResizeHandle.swift
//  Ravel
//
//  Created by weixi on 2026/09/18.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit
import SwiftUI

struct RevisionInspectorResizeHandle: NSViewRepresentable {
    func makeNSView(context _: Context) -> RevisionInspectorResizeView {
        RevisionInspectorResizeView()
    }

    func updateNSView(_: RevisionInspectorResizeView, context _: Context) {}
}

final class RevisionInspectorResizeView: NSView {
    private weak var resizingSplitView: NSSplitView?
    private var dragOriginY: CGFloat = 0
    private var initialPosition: CGFloat = 0

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if enclosingSplitView != nil {
            addCursorRect(bounds, cursor: resizingSplitView == nil ? .openHand : .closedHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let splitView = enclosingSplitView, let history = splitView.arrangedSubviews.first else { return }
        resizingSplitView = splitView
        dragOriginY = event.locationInWindow.y
        initialPosition = history.frame.height
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let resizingSplitView else { return }
        // Window coordinates stay stable as the header moves with the divider.
        let distance = dragOriginY - event.locationInWindow.y
        resizingSplitView.setPosition(initialPosition + distance, ofDividerAt: 0)
        NSCursor.closedHand.set()
    }

    override func mouseUp(with event: NSEvent) {
        resizingSplitView = nil
        window?.invalidateCursorRects(for: self)
        let isInside = bounds.contains(convert(event.locationInWindow, from: nil))
        (isInside ? NSCursor.openHand : NSCursor.arrow).set()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if resizingSplitView != nil {
            NSCursor.arrow.set()
        }
        resizingSplitView = nil
        window?.invalidateCursorRects(for: self)
    }

    private var enclosingSplitView: NSSplitView? {
        var ancestor = superview
        while let view = ancestor {
            if let splitView = view as? NSSplitView, !splitView.isVertical, splitView.arrangedSubviews.count == 2 {
                return splitView
            }
            ancestor = view.superview
        }
        return nil
    }
}
