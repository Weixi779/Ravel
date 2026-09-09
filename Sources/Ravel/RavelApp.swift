// Created by weixi on 2026/09/09.

import AppKit
import SwiftUI

#if compiler(<6.2)
#error("Ravel requires Swift 6.2 or newer.")
#endif

@main
struct RavelApp: App {
    @State private var session = LogSession()

    var body: some Scene {
        Window("Ravel", id: "repository") {
            RepositoryView(session: session)
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
                Button("Open Repository…", systemImage: "folder.badge.plus") {
                    RepositoryPanel.open(using: session)
                }
                .keyboardShortcut("o")
                Menu("Open Recent") {
                    ForEach(session.recentPaths, id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) {
                            session.open(URL(fileURLWithPath: path, isDirectory: true))
                        }
                    }
                }
                .disabled(session.recentPaths.isEmpty)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh Log", systemImage: "arrow.clockwise") { session.refresh() }
                    .keyboardShortcut("r")
                    .disabled(session.repositoryURL == nil || session.isLoading)
                Button("Go to Working Copy", systemImage: "scope") { session.selectWorkingCopy() }
                    .keyboardShortcut("0")
                    .disabled(session.log?.revisions.contains(where: \.isWorkingCopy) != true)
            }
            CommandGroup(after: .appSettings) {
                Button("Choose jj Executable…") { RepositoryPanel.chooseExecutable(using: session) }
            }
        }
    }
}

@MainActor
enum RepositoryPanel {
    static func open(using session: LogSession) {
        let panel = NSOpenPanel()
        panel.title = "Open Repository"
        panel.message = "Choose a Jujutsu workspace."
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = session.repositoryURL
        if panel.runModal() == .OK, let url = panel.url { session.open(url) }
    }

    static func chooseExecutable(using session: LogSession) {
        let panel = NSOpenPanel()
        panel.title = "Choose jj Executable"
        panel.message = "Select the jj program installed on this Mac."
        panel.prompt = "Use jj"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url { session.setExecutable(url) }
    }
}
