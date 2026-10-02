//
//  RavelAppDelegate.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit

@MainActor
final class RavelAppDelegate: NSObject, NSApplicationDelegate {
    private var dockIcon: DockIconController?

    func applicationDidFinishLaunching(_: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        dockIcon = DockIconController(application: .shared)
    }

    func applicationWillTerminate(_: Notification) {
        dockIcon?.stop()
    }
}
