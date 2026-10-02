//
//  DockIconTests.swift
//  Ravel
//
//  Created by weixi on 2026/09/10.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import AppKit
@testable import Ravel
import Testing

@MainActor
struct DockIconTests {
    @Test
    func dockFollowsAppearanceChangesWhileRunning() async throws {
        // This only changes the test host's appearance, never system settings.
        let application = NSApplication.shared
        let originalAppearance = application.appearance
        let originalContent = application.dockTile.contentView
        defer { application.appearance = originalAppearance }

        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))
        application.appearance = light
        let controller = try #require(DockIconController(application: application))
        defer { controller.stop() }
        let view = try #require(application.dockTile.contentView as? NSImageView)
        let initialImage = try #require(view.image)
        #expect(view.appearance?.name == .aqua)
        try expectVisibleIcon(in: application.dockTile)

        // The Dock can resize its detached view without an appearance change
        // or another call to the controller's refresh method.
        let content = try #require(application.dockTile.contentView)
        let originalSize = content.frame.size
        content.setFrameSize(.zero)
        content.setFrameSize(originalSize)
        application.dockTile.display()
        try expectVisibleIcon(in: application.dockTile)

        application.appearance = dark
        try await waitUntil { view.appearance?.name == .darkAqua }
        #expect(view.image !== initialImage)
        try expectVisibleIcon(in: application.dockTile)

        application.appearance = light
        try await waitUntil { view.appearance?.name == .aqua }
        #expect(view.image === initialImage)
        try expectVisibleIcon(in: application.dockTile)

        // Queue an update and stop before it executes; it must not reinstall
        // or redraw the detached view after the observer has been removed.
        application.appearance = dark
        controller.stop()
        await Task.yield()
        #expect(application.dockTile.contentView === originalContent)
        #expect(view.image === initialImage)
    }

    private func expectVisibleIcon(in tile: NSDockTile) throws {
        let content = try #require(tile.contentView)
        let imageView = try #require(content as? NSImageView)
        #expect(imageView.frame.width > 0 && imageView.frame.height > 0,
                "Dock image frame is empty: \(imageView.frame); tile bounds: \(content.bounds)")
        let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        #expect(center.alphaComponent > 0.9, "The Dock icon center must be opaque, not invisible")
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Dock icon did not follow the appearance change")
    }
}
