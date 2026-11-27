//
//  RepositoryView.swift
//  Ravel
//
//  Created by weixi on 2026/09/09.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit
import Localization
import SwiftUI

struct RepositoryView: View {
    @Bindable var session: LogSession
    let diffSession: RevisionChangesSession

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 290)
        } detail: {
            VStack(spacing: 0) {
                if let error = session.errorMessage {
                    errorNotice(error)
                }

                if let log = session.log {
                    history(log)
                } else if session.isLoading {
                    ProgressView(I18n.repositoryOpening)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    welcome
                }
                statusBar
            }
            .background(Color(nsColor: .textBackgroundColor))
            .navigationTitle(session.repositoryURL?.lastPathComponent ?? "Ravel")
            .navigationSubtitle(session.repositoryURL.map { Text(verbatim: $0.deletingLastPathComponent().path) } ?? Text(I18n.repositorySubtitle))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { RepositoryPanel.open(using: session) } label: {
                        Label(I18n.repositoryOpenTitle, systemImage: "folder.badge.plus")
                    }
                    .help(I18n.repositoryOpenHelp)
                    Button { session.selectWorkingCopy() } label: {
                        Label(I18n.historyWorkingCopy, systemImage: "scope")
                    }
                    .disabled(session.log?.revisions.contains(where: \.isWorkingCopy) != true)
                    .help(I18n.historyWorkingCopyHelp)
                    Button { session.refresh() } label: {
                        Label(I18n.commonRefresh, systemImage: "arrow.clockwise")
                    }
                    .disabled(session.repositoryURL == nil || session.isLoading)
                    .help(I18n.historyRefreshHelp)
                }
            }
        }
        .sheet(item: $session.describeTarget) { target in
            RevisionDescriptionEditor(revision: target.revision) {
                session.describeTarget = nil
            } save: { draft in
                Task { await session.saveDescription(draft, for: target) }
            }
        }
        .alert(I18n.historyCommandResult, isPresented: Binding(
            get: { session.commandNotice != nil },
            set: { if !$0 { session.commandNotice = nil } },
        )) {} message: {
            Text(verbatim: session.commandNotice ?? "")
        }
    }

    private var sidebar: some View {
        List {
            Section(I18n.repositoryWorkspace) {
                Label(I18n.historyTitle, systemImage: "point.3.connected.trianglepath.dotted")
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
                    .padding(.vertical, 3)
                    .listRowBackground(Color.accentColor.opacity(0.12))
            }
            if !session.recentPaths.isEmpty {
                Section(I18n.repositoryRepositories) {
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
                            Button(I18n.repositoryRemoveRecent) { session.forget(path) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button { RepositoryPanel.open(using: session) } label: {
                Label(I18n.repositoryOpen, systemImage: "plus")
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
            Text(session.errorMessage == nil ? I18n.repositoryWelcomeTitle : I18n.repositoryWelcomeRecovery)
                .font(.system(size: 24, weight: .semibold))
            Text(I18n.repositoryWelcomeDetail)
                .foregroundStyle(.secondary)
            Button(I18n.repositoryOpen) { RepositoryPanel.open(using: session) }
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
                Text(I18n.historyTitle).font(.headline)
                Text(I18n.historyChangeCount(log.revisions.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !log.hasMore {
                    Text(I18n.historyReachedRoot)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 39)
            Divider()

            if log.revisions.isEmpty {
                ContentUnavailableView(I18n.historyEmptyTitle, systemImage: "line.3.horizontal.decrease", description: Text(I18n.historyEmptyDetail))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VSplitView {
                    VStack(spacing: 0) {
                        RevisionTable(
                            log: log,
                            selection: $session.selectedRevisionID,
                            graphStyle: session.graphStyle,
                            menuForRevision: { revision in
                                let target = HistoryRevision(repositoryURL: log.repositoryURL, operationID: log.operationID, revision: revision)
                                return RevisionActionMenu.describe { session.beginDescribe(target) }
                            },
                            loadMore: { session.loadMore() },
                        )
                        if session.isLoadingMore || session.pageErrorMessage != nil || log.hasMore {
                            Divider()
                            HStack {
                                if session.isLoadingMore {
                                    ProgressView().controlSize(.small)
                                    Text(I18n.historyLoadingMore)
                                } else if let error = session.pageErrorMessage {
                                    Text(error).lineLimit(2).textSelection(.enabled)
                                    Button(I18n.commonRetry) { session.loadMore(retry: true) }
                                } else {
                                    Button(I18n.historyLoadMore) { session.loadMore() }
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(minHeight: 180, idealHeight: 350)
                    RevisionInspectorView(revision: session.selectedRevision, request: session.diffRequest, diff: diffSession)
                        .frame(minHeight: 240, idealHeight: 350)
                }
            }
        }
    }

    private func errorNotice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(I18n.commonRetry) { session.refresh() }
                .disabled(session.isLoading)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if session.isLoading {
                ProgressView().controlSize(.mini)
                Text(I18n.historyRefreshing)
            } else if session.errorMessage != nil {
                Image(systemName: "exclamationmark.circle")
                Text(session.log == nil ? I18n.historyLoadFailed : I18n.historyRefreshFailed)
            } else if let log = session.log {
                Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                Text(log.backendVersion)
                Text("·").foregroundStyle(.tertiary)
                Text(I18n.historyRecordedState)
                    .help(I18n.historyRecordedStateHelp)
            } else {
                Text(I18n.historyReady)
            }
            Spacer()
            if let date = session.lastUpdated {
                Text(I18n.historyUpdated(date.formatted(.dateTime.hour().minute().second())))
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
