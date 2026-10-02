//
//  RevisionInspectorResizeTests.swift
//  Ravel
//
//  Created by weixi on 2026/09/18.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit
@testable import Ravel
import SwiftUI
import Testing
import UserDefaultsKit

@MainActor
struct RevisionInspectorResizeTests {
    @Test
    func headerDragsResizeHistoryAndRespectPaneLimits() async throws {
        let suite = "RavelInspectorResizeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let options = DiffViewOptions(store: UserDefaultsStore(defaults: defaults))
        let session = RevisionChangesSession(loader: { _ in RevisionDiff(files: []) }, fileLoader: { _, _ in
            throw TestFailure("No file should load without a revision")
        })
        let log = try repositoryLog("/Ravel", revisions: [revision("sample")])
        let host = NSHostingView(rootView: VSplitView {
            RevisionTable(log: log, selection: .constant(nil))
                .frame(minHeight: 180, idealHeight: 350)

            RevisionInspectorView(revision: nil, request: nil, diff: session)
                .environment(options)
                .frame(minHeight: 240, idealHeight: 350)
        })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        host.layoutSubtreeIfNeeded()

        let handle = try #require(descendant(RevisionInspectorResizeView.self, in: host))
        let split = try #require(descendant(NSSplitView.self, in: host))
        let history = try #require(split.arrangedSubviews.first)
        let inspector = try #require(split.arrangedSubviews.last)
        let initialHeight = history.frame.height

        func dragHeader(by distance: CGFloat) throws {
            let origin = handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
            let destination = NSPoint(x: origin.x, y: origin.y + distance)
            for (type, location) in [(NSEvent.EventType.leftMouseDown, origin), (.leftMouseDragged, destination), (.leftMouseUp, destination)] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                window.sendEvent(event)
            }
        }

        try dragHeader(by: 80)
        #expect(abs(history.frame.height - (initialHeight - 80)) < 1)

        try dragHeader(by: -40)
        #expect(abs(history.frame.height - (initialHeight - 40)) < 1)

        try dragHeader(by: 1000)
        #expect(abs(history.frame.height - 180) < 1)

        try dragHeader(by: -1000)
        #expect(abs(inspector.frame.height - 240) < 1)
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        for child in view.subviews {
            if let result = descendant(type, in: child) { return result }
        }
        return nil
    }
}
