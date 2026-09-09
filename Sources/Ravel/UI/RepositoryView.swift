// Created by weixi on 2026/09/09.

import AppKit
import SwiftUI

struct RepositoryView: View {
    @Bindable var session: LogSession

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 290)
        } detail: {
            VStack(spacing: 0) {
                if let error = session.errorMessage {
                    notice(error, symbol: "exclamationmark.triangle", isError: true)
                }
                if let warning = session.log?.warning {
                    notice(warning, symbol: "exclamationmark.bubble", isError: false)
                }

                if let log = session.log {
                    history(log)
                } else if session.isLoading {
                    ProgressView("Opening repository…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    welcome
                }
                statusBar
            }
            .background(Color(nsColor: .textBackgroundColor))
            .navigationTitle(session.repositoryURL?.lastPathComponent ?? "Ravel")
            .navigationSubtitle(session.repositoryURL?.deletingLastPathComponent().path ?? "Jujutsu for Mac")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { RepositoryPanel.open(using: session) } label: {
                        Label("Open Repository", systemImage: "folder.badge.plus")
                    }
                    .help("Open Repository (⌘O)")
                    Button { session.selectWorkingCopy() } label: {
                        Label("Working Copy", systemImage: "scope")
                    }
                    .disabled(session.log?.revisions.contains(where: \.isWorkingCopy) != true)
                    .help("Go to Working Copy (⌘0)")
                    Button { session.refresh() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(session.repositoryURL == nil || session.isLoading)
                    .help("Refresh Log (⌘R)")
                }
            }
        }
    }

    private var sidebar: some View {
        List {
            Section("Workspace") {
                Label("History", systemImage: "point.3.connected.trianglepath.dotted")
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
                    .padding(.vertical, 3)
                    .listRowBackground(Color.accentColor.opacity(0.12))
            }
            if !session.recentPaths.isEmpty {
                Section("Repositories") {
                    ForEach(session.recentPaths, id: \.self) { path in
                        let url = URL(fileURLWithPath: path, isDirectory: true)
                        Button { session.open(url) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                Text(url.lastPathComponent).lineLimit(1)
                                Spacer(minLength: 0)
                                if session.repositoryURL?.path == path {
                                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                        .help(path)
                        .contextMenu {
                            Button("Remove from Recent") { session.forget(path) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button { RepositoryPanel.open(using: session) } label: {
                Label("Open Repository…", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 100, height: 100)
            Text(session.errorMessage == nil ? "Your changes, in view." : "Open a Jujutsu workspace")
                .font(.system(size: 24, weight: .semibold))
            Text("See your history, follow each change, and find your place.")
                .foregroundStyle(.secondary)
            Button("Open Repository…") { RepositoryPanel.open(using: session) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            Text("⌘O").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func history(_ log: RepositoryLog) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("History").font(.headline)
                Text("\(log.revisions.count) changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if log.isLimited {
                    Text("Showing first \(JJClient.revisionLimit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 39)
            Divider()

            if log.revisions.isEmpty {
                ContentUnavailableView("No revisions", systemImage: "line.3.horizontal.decrease", description: Text("The repository's log selection contains no revisions."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VSplitView {
                    RevisionTable(log: log, selection: $session.selectedRevisionID)
                        .frame(minHeight: 180, idealHeight: 350)
                    RevisionInspector(revision: session.selectedRevision, request: session.diffRequest)
                        .frame(minHeight: 240, idealHeight: 350)
                }
            }
        }
    }

    private func notice(_ text: String, symbol: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(isError ? Color.orange : Color.secondary)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isError {
                Button("Locate jj…") { RepositoryPanel.chooseExecutable(using: session) }
                Button("Retry") { session.refresh() }
                    .disabled(session.isLoading)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(isError ? 0.08 : 0.04))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if session.isLoading {
                ProgressView().controlSize(.mini)
                Text("Refreshing…")
            } else if session.errorMessage != nil {
                Image(systemName: "exclamationmark.circle")
                Text(session.log == nil ? "Unable to load repository" : "Refresh failed · showing previous log")
            } else if let log = session.log {
                Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                Text(log.jjVersion)
                Text("·").foregroundStyle(.tertiary)
                Text("Recorded repository state")
                    .help("Refresh reads jj's recorded state without snapshotting your working directory.")
            } else {
                Text("Ready")
            }
            Spacer()
            if let date = session.lastUpdated {
                Text("Updated \(date, format: .dateTime.hour().minute().second())")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 29)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }
}
