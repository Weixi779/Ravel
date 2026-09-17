// Created by weixi on 2026/09/09.

import AppKit
import SwiftUI
import Localization

#if compiler(<6.2)
#error("Ravel requires Swift 6.2 or newer.")
#endif

@main
struct RavelApp: App {
    @NSApplicationDelegateAdaptor(RavelAppDelegate.self) private var appDelegate
    private let workspace: RepositoryWorkspace
    @State private var session: LogSession

    init() {
        let workspace = RepositoryWorkspace()
        self.workspace = workspace
        _session = State(initialValue: LogSession(workspace: workspace))
    }

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
                Button(String(localized: I18n.repositoryOpen), systemImage: "folder.badge.plus") {
                    RepositoryPanel.open(using: session)
                }
                .keyboardShortcut("o")
                Menu(String(localized: I18n.repositoryOpenRecent)) {
                    ForEach(session.recentPaths, id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) {
                            session.open(URL(fileURLWithPath: path, isDirectory: true))
                        }
                    }
                }
                .disabled(session.recentPaths.isEmpty)
            }
            CommandGroup(after: .toolbar) {
                Button(String(localized: I18n.historyRefreshLog), systemImage: "arrow.clockwise") { session.refresh() }
                    .keyboardShortcut("r")
                    .disabled(session.repositoryURL == nil || session.isLoading)
                Button(String(localized: I18n.historyGoToWorkingCopy), systemImage: "scope") { session.selectWorkingCopy() }
                    .keyboardShortcut("0")
                    .disabled(session.log?.revisions.contains(where: \.isWorkingCopy) != true)
            }
            CommandGroup(after: .appSettings) {
                Button(String(localized: I18n.repositoryChooseExecutable)) { RepositoryPanel.chooseExecutable(using: session) }
            }
        }

        Settings {
            Form {
                Picker(String(localized: I18n.historyPageSize), selection: Binding(
                    get: { session.historyPageSize },
                    set: { session.setHistoryPageSize($0) }
                )) {
                    ForEach(LogSession.historyPageSizes, id: \.self) { size in
                        Text(size.formatted()).tag(size)
                    }
                }
                Text(I18n.historyPageSizeHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .frame(width: 440)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
final class RavelAppDelegate: NSObject, NSApplicationDelegate {
    private var dockIcon: DockIconController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        dockIcon = DockIconController(application: .shared)
    }

    func applicationWillTerminate(_ notification: Notification) {
        dockIcon?.stop()
    }
}

@MainActor
enum RepositoryPanel {
    static func open(using session: LogSession) {
        let panel = NSOpenPanel()
        panel.title = String(localized: I18n.repositoryOpenTitle)
        panel.message = String(localized: I18n.repositoryChooseWorkspace)
        panel.prompt = String(localized: I18n.commonOpen)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = session.repositoryURL
        if panel.runModal() == .OK, let url = panel.url { session.open(url) }
    }

    static func chooseExecutable(using session: LogSession) {
        let panel = NSOpenPanel()
        panel.title = String(localized: I18n.repositoryExecutableTitle)
        panel.message = String(localized: I18n.repositoryExecutableHelp)
        panel.prompt = String(localized: I18n.repositoryUseExecutable)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url { session.setExecutable(url) }
    }
}
