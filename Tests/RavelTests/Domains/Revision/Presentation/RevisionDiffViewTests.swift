// Created by weixi on 2026/09/17.

import AppKit
@testable import Ravel
import SwiftUI
import Testing

@MainActor
struct RevisionDiffViewTests {
    @Test
    func shortDiffDecoratesOnFirstWindowAttachmentWithoutScrolling() throws {
        let diff = try RevisionPatchParser.parse("@@ -1,2 +1,1 @@\n-old\n+new\n-\n")
        let host = NSHostingView(rootView: RevisionDiffView(diff: RevisionDiffPresentation(diff, fileName: "Sample.swift")))
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
        let long = try RevisionPatchParser.parse("@@ -0,0 +1,1000 @@\n" + (1 ... 1000).map { "+line \($0)\n" }.joined())
        let short = try RevisionPatchParser.parse("@@ -1,2 +1,2 @@\n-old\n+new\n context\n")
        let host = NSHostingView(rootView: RevisionDiffView(diff: RevisionDiffPresentation(long, fileName: "Sample.swift")))
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

        host.rootView = RevisionDiffView(diff: RevisionDiffPresentation(short, fileName: "Sample.swift"))
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
        let diff = try RevisionPatchParser.parse(patch)
        let host = NSHostingView(rootView: RevisionDiffView(diff: RevisionDiffPresentation(diff, fileName: "Sample.swift")))
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

        host.rootView = RevisionDiffView(diff: RevisionDiffPresentation(diff, fileName: "Sample.swift"), showsChangeMarkers: true)
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        #expect(descendant(DiffReadOnlyTextView.self, in: host) === text)
        #expect(text.textSelection == selection)
        #expect(abs(scroll.contentView.bounds.origin.y - origin.y) < 1)
        #expect(scroll.verticalRulerView?.ruleThickness == width)
        #expect(text.document?.row(atUTF16Offset: (text.text ?? "").utf16.count - 1)?.line.newNumber == 1000)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func smallScrollsKeepTheBottomRowsPainted(appearance: NSAppearance.Name) async throws {
        let diff = try RevisionPatchParser.parse("@@ -0,0 +1,1000 @@\n" + (1 ... 1000).map { "+let value\($0) = \($0) // comment\n" }.joined())
        let host = NSHostingView(rootView: RevisionDiffView(diff: RevisionDiffPresentation(diff, fileName: "Sample.swift")))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let text = try #require(descendant(DiffReadOnlyTextView.self, in: host))
        let scroll = try #require(text.enclosingScrollView)
        for distance in [8.0, 24.0, 48.0, 80.0, 2000.0] {
            // AppKit reserves the ruler using the clip view's horizontal origin.
            // A vertical gesture must preserve that origin, which can be negative.
            scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: distance))
            scroll.reflectScrolledClipView(scroll.contentView)
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            let visible = text.visibleRect
            #expect(text.convert(NSPoint.zero, to: scroll).x >= (scroll.verticalRulerView?.frame.maxX ?? 0))
            #expect(abs(text.diffBackground.frame.minY - visible.minY) < 1)
            #expect(text.diffBackground.frame.maxY >= visible.maxY - 1)
            let bottom = try #require(text.visibleRows.last { $0.frame.intersects(visible) && $0.row.line.kind == .addition })
            let point = text.diffBackground.convert(NSPoint(x: visible.maxX - 12, y: min(bottom.frame.midY, visible.maxY - 2)), from: text)
            let image = try #require(text.diffBackground.bitmapImageRepForCachingDisplay(in: text.diffBackground.bounds))
            text.diffBackground.cacheDisplay(in: text.diffBackground.bounds, to: image)
            let x = min(image.pixelsWide - 1, max(0, Int(point.x * CGFloat(image.pixelsWide) / text.diffBackground.bounds.width)))
            let y = min(image.pixelsHigh - 1, max(0, Int(point.y * CGFloat(image.pixelsHigh) / text.diffBackground.bounds.height)))
            let color = try #require(image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            #expect(color.alphaComponent > 0.05)
            #expect(color.greenComponent > color.redComponent)
        }
        if let directory = ProcessInfo.processInfo.environment["RAVEL_RENDER_OUTPUT"],
           let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        {
            host.cacheDisplay(in: host.bounds, to: image)
            try image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("ravel-scroll-\(appearance.rawValue).png"))
        }
    }

    @Test
    func splitReadersAlignAndSynchronizeAfterScrollingEitherSide() async throws {
        let diff = try RevisionPatchParser.parse("@@ -1,1000 +1,1000 @@\n" + (1 ... 1000).map { "-old \($0)\n+new \($0)\n" }.joined())
        let host = NSHostingView(rootView: RevisionDiffView(diff: RevisionDiffPresentation(diff, fileName: "Sample.swift"), sideBySide: true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let texts = descendants(DiffReadOnlyTextView.self, in: host)
        #expect(texts.count == 2)
        let left = try #require(texts.first?.enclosingScrollView)
        let right = try #require(texts.last?.enclosingScrollView)
        let split = try #require(descendant(NSSplitView.self, in: host))
        split.setPosition(350, ofDividerAt: 0)
        host.layoutSubtreeIfNeeded()
        #expect(left.bounds.width < right.bounds.width)
        let labels = descendants(NSTextField.self, in: split).filter { !$0.isEditable }
        #expect(labels.count == 2)
        #expect(abs(labels[0].frame.width - left.frame.width) < 1)
        #expect(abs(labels[1].frame.width - right.frame.width) < 1)
        for (source, target) in [(left, right), (right, left)] {
            source.contentView.scroll(to: NSPoint(x: source.contentView.bounds.minX, y: 800))
            source.reflectScrolledClipView(source.contentView)
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            #expect(abs(source.contentView.bounds.minY - target.contentView.bounds.minY) < 1)
            let old = try #require(texts[0].visibleRows.first { $0.frame.intersects(texts[0].visibleRect) && $0.row.line.oldNumber != nil })
            let new = try #require(texts[1].visibleRows.first { $0.frame.intersects(texts[1].visibleRect) && $0.row.line.newNumber != nil })
            #expect(old.row.line.oldNumber == new.row.line.newNumber, "old frame: \(old.frame), new frame: \(new.frame), left visible: \(texts[0].visibleRect), right visible: \(texts[1].visibleRect), left view: \(texts[0].frame), right view: \(texts[1].frame), clip left: \(left.contentView.bounds), clip right: \(right.contentView.bounds)")
            #expect(abs(old.frame.minY - new.frame.minY) < 1)
        }
    }

    private func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(type, in: $0) }
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        for child in view.subviews {
            if let result = descendant(type, in: child) { return result }
        }
        return nil
    }
}
