//
//  RavelApp.swift
//  Ravel
//
//  Created by weixi on 2026/09/09.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import AppKit
import Localization
import SwiftUI

#if compiler(<6.2)
    #error("Ravel requires Swift 6.2 or newer.")
#endif

@main
struct RavelApp: App {
    @NSApplicationDelegateAdaptor(RavelAppDelegate.self) private var appDelegate
    private let workspace: RepositoryWorkspace
    @State private var session: LogSession
    @State private var diffSession: RevisionChangesSession
    @State private var diffOptions = DiffViewOptions()

    init() {
        let workspace = RepositoryWorkspace()
        self.workspace = workspace
        _session = State(initialValue: LogSession(workspace: workspace))
        _diffSession = State(initialValue: RevisionChangesSession(
            loader: { try await workspace.diff($0) },
            fileLoader: { try await workspace.fileDiff($0, file: $1) },
            statisticsLoader: { try await workspace.diffStatistics($0) },
        ))
    }

    var body: some Scene {
        Window("Ravel", id: "repository") {
            RepositoryView(session: session, diffSession: diffSession)
                .environment(diffOptions)
                .frame(minWidth: 920, minHeight: 560)
                .task {
                    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                    session.restoreIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    session.refreshIfNeeded()
                }
        }
        .defaultSize(width: 1240, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(I18n.repositoryOpen, systemImage: "folder.badge.plus") {
                    RepositoryPanel.open(using: session)
                }
                .keyboardShortcut("o")
                Menu(I18n.repositoryOpenRecent) {
                    ForEach(session.recentPaths, id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) {
                            session.open(URL(fileURLWithPath: path, isDirectory: true))
                        }
                    }
                }
                .disabled(session.recentPaths.isEmpty)
            }
            CommandGroup(after: .toolbar) {
                Button(I18n.historyRefreshLog, systemImage: "arrow.clockwise") { session.refresh() }
                    .keyboardShortcut("r")
                    .disabled(session.repositoryURL == nil || session.isLoading)
                Button(I18n.historyGoToWorkingCopy, systemImage: "scope") { session.selectWorkingCopy() }
                    .keyboardShortcut("0")
                    .disabled(session.log?.revisions.contains(where: \.isWorkingCopy) != true)
            }
        }

        Settings {
            SettingsView(session: session, diffOptions: diffOptions)
        }
    }
}
