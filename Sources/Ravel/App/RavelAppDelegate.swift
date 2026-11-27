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
    var workspace: RepositoryWorkspace?
    private var terminating = false
    private var dockIcon: DockIconController?

    func applicationDidFinishLaunching(_: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        dockIcon = DockIconController(application: .shared)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let workspace else { return .terminateNow }
        if !terminating {
            terminating = true
            Task {
                await workspace.close()
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_: Notification) {
        dockIcon?.stop()
    }
}
