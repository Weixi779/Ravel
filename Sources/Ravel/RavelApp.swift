// Created by weixi on 2026/09/09.

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
    @State private var diffSession: DiffSession
    @State private var diffOptions = DiffViewOptions()

    init() {
        let workspace = RepositoryWorkspace()
        self.workspace = workspace
        _session = State(initialValue: LogSession(workspace: workspace))
        _diffSession = State(initialValue: DiffSession(loader: workspace.diff, fileLoader: workspace.fileDiff))
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
        }

        Settings {
            Form {
                Picker(String(localized: I18n.historyPageSize), selection: Binding(
                    get: { session.historyPageSize },
                    set: { session.setHistoryPageSize($0) },
                )) {
                    ForEach(LogSession.historyPageSizes, id: \.self) { size in
                        Text(size.formatted()).tag(size)
                    }
                }
                Text(I18n.historyPageSizeHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Section {
                    DiffReadingSettings(options: diffOptions)
                }
            }
            .formStyle(.grouped)
            .frame(width: 440)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DiffReadingSettings: View {
    @Bindable var options: DiffViewOptions
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Toggle(String(localized: I18n.diffShowMarkers), isOn: Binding(
            get: { options.showsChangeMarkers ?? differentiateWithoutColor },
            set: { options.showsChangeMarkers = $0 },
        ))
        Button(String(localized: I18n.diffMarkersFollowSystem)) { options.showsChangeMarkers = nil }
            .disabled(options.showsChangeMarkers == nil)
    }
}

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
}
