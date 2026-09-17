// Created by weixi on 2026/09/17.

import AppKit
@testable import Ravel
import SwiftUI
import Testing

@MainActor
struct DiffTextViewTests {
    @Test
    func shortDiffDecoratesOnFirstWindowAttachmentWithoutScrolling() throws {
        let diff = try FileDiff(patch: "@@ -1,2 +1,1 @@\n-old\n+new\n-\n")
        let host = NSHostingView(rootView: DiffTextView(diff: diff))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 320)
        // SwiftUI may construct and lay out the reader before it belongs to a window.
        host.layoutSubtreeIfNeeded()
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let text = try #require(descendant(DiffReadOnlyTextView.self, in: host))
        #expect(text.visibleRows.contains { $0.row.line.kind == .addition })
        #expect(text.visibleRows.contains { $0.row.line.oldNumber == 2 })
        let last = try #require(text.visibleRows.last { $0.row.line.oldNumber == 2 })
        let addition = try #require(text.visibleRows.first { $0.row.line.kind == .addition })
        #expect(abs(last.frame.height - addition.frame.height) < 1)
        let original = text.text
        text.textSelection = NSRange(location: 0, length: 1)
        text.setAccessibilitySelectedText("replacement")
        #expect(text.text == original)
    }

    @Test
    func replacingAScrolledDocumentResetsGutterAndViewport() async throws {
        let long = try FileDiff(patch: "@@ -0,0 +1,1000 @@\n" + (1 ... 1000).map { "+line \($0)\n" }.joined())
        let short = try FileDiff(patch: "@@ -1,2 +1,2 @@\n-old\n+new\n context\n")
        let host = NSHostingView(rootView: DiffTextView(diff: long))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 280),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let text = try #require(descendant(DiffReadOnlyTextView.self, in: host))
        let scroll = try #require(text.enclosingScrollView)
        text.scrollToEndOfDocument(nil)
        scroll.layoutSubtreeIfNeeded()
        #expect(scroll.contentView.bounds.minY > 0)

        host.rootView = DiffTextView(diff: short)
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        #expect(text.contentID == short.id)
        #expect(abs(scroll.contentView.bounds.minY) < 1)
        #expect(text.visibleRows.count == 4)
        #expect(text.visibleRows.allSatisfy { ($0.row.line.newNumber ?? 0) <= 2 })
        #expect(scroll.clipsToBounds)
        #expect(scroll.verticalRulerView?.clipsToBounds == true)
    }

    @Test
    func thousandLineReaderKeepsSelectionAndScrollWhenMarkersChange() async throws {
        let patch = "@@ -0,0 +1,1000 @@\n" + (1 ... 1000).map { "+let value\($0) = \($0)\n" }.joined()
        let diff = try FileDiff(patch: patch)
        let host = NSHostingView(rootView: DiffTextView(diff: diff))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 320),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let text = try #require(descendant(DiffReadOnlyTextView.self, in: host))
        let scroll = try #require(text.enclosingScrollView)
        text.layoutSubtreeIfNeeded()
        #expect(!text.isEditable)
        #expect(text.isSelectable)
        #expect(text.document?.rows.count == 1001)
        #expect(text.text?.contains("\nlet value1 = 1\n") == true)
        #expect(text.text?.contains("\n+let") == false)

        text.textSelection = NSRange(location: 30, length: 20)
        text.scrollToEndOfDocument(nil)
        scroll.layoutSubtreeIfNeeded()
        let selection = text.textSelection
        let origin = scroll.contentView.bounds.origin
        let width = scroll.verticalRulerView?.ruleThickness
        #expect(origin.y > 0)
        #expect(!text.visibleRows.isEmpty)
        #expect(text.visibleRows.count < 1000)

        host.rootView = DiffTextView(diff: diff, showsChangeMarkers: true)
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        #expect(descendant(DiffReadOnlyTextView.self, in: host) === text)
        #expect(text.textSelection == selection)
        #expect(abs(scroll.contentView.bounds.origin.y - origin.y) < 1)
        #expect(scroll.verticalRulerView?.ruleThickness == width)
        #expect(text.document?.row(atUTF16Offset: (text.text ?? "").utf16.count - 1)?.line.newNumber == 1000)
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        for child in view.subviews {
            if let result = descendant(type, in: child) { return result }
        }
        return nil
    }
}
