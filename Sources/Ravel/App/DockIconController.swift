//
//  DockIconController.swift
//  Ravel
//
//  Created by weixi on 2026/09/10.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit

/// Keeps the running app's Dock icon in sync with system appearance.
@MainActor
final class DockIconController {
    private let application: NSApplication
    private let lightImage: NSImage
    private let darkImage: NSImage
    private let imageView: NSImageView
    private let previousContentView: NSView?
    private var appearanceObservation: NSKeyValueObservation?
    private var isActive = true

    init?(application: NSApplication, bundle: Bundle = .main) {
        guard let lightURL = bundle.url(forResource: "DockIconLight", withExtension: "png"),
              let darkURL = bundle.url(forResource: "DockIconDark", withExtension: "png"),
              let lightImage = NSImage(contentsOf: lightURL),
              let darkImage = NSImage(contentsOf: darkURL) else { return nil }

        self.application = application
        self.lightImage = Self.paddedIcon(lightImage)
        self.darkImage = Self.paddedIcon(darkImage)
        previousContentView = application.dockTile.contentView
        imageView = NSImageView(frame: NSRect(origin: .zero, size: application.dockTile.size))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        // The Dock renders this detached view directly. Keep the image at the
        // root, without a container that depends on window-driven layout.
        application.dockTile.contentView = imageView
        refresh()

        appearanceObservation = application.observe(\.effectiveAppearance) { [weak self] _, _ in
            // KVO is not actor-isolated. Read the latest appearance on MainActor,
            // so queued callbacks cannot restore an obsolete appearance.
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func stop() {
        isActive = false
        appearanceObservation = nil
        if application.dockTile.contentView === imageView {
            application.dockTile.contentView = previousContentView
            application.dockTile.display()
        }
    }

    private func refresh() {
        guard isActive else { return }
        let appearance = application.effectiveAppearance
        // Dock content views have no window to propagate appearance to them.
        imageView.appearance = appearance
        imageView.image = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? darkImage : lightImage
        application.dockTile.display()
    }

    private static func paddedIcon(_ source: NSImage) -> NSImage {
        // Composer exports only the tile; include Dock padding in its drawing
        // canvas so the content view needs no child views or constraints.
        NSImage(size: source.size, flipped: false) { bounds in
            source.draw(in: bounds.insetBy(dx: bounds.width * 0.1, dy: bounds.height * 0.1))
            return true
        }
    }
}
