//
//  LogSession.swift
//  Ravel
//
//  Created by weixi on 2026/09/09.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
import Localization
import Logger
import Observation
import UserDefaultsKit
import UserDefaultsKitMacros

@MainActor
@Observable
final class LogSession {
    private static let logger = Logger.make(category: "Repository")
    typealias Loader = @Sendable (URL, Int) async throws -> any HistoryQuery
    static let historyPageSizes = [100, 200, 500, 1000, 5000]

    private(set) var repositoryURL: URL?
    private(set) var log: RepositoryLog?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isLoadingMore = false
    private(set) var pageErrorMessage: String?
    @ObservedDefault(.recentWorkspacePaths, store: \Self.store)
    @ObservationIgnored private(set) var recentPaths: [String]
    private(set) var lastUpdated: Date?
    var selectedRevisionID: String?
    var describeTarget: HistoryRevision?
    var commandRequest: HistoryCommandRequest?
    var commandNotice: String?
    private(set) var isSubmitting = false

    @ObservedDefault(.lastWorkspacePath, store: \Self.store)
    @ObservationIgnored private var lastWorkspacePath: String?

    @ObservedDefault(.historyPageSize, store: \Self.store)
    @ObservationIgnored private var storedHistoryPageSize: Int

    @ObservedDefault(.historyGraphStyle, store: \Self.store)
    @ObservationIgnored private var storedGraphStyle: String

    var graphStyle: HistoryGraphStyle {
        get { HistoryGraphStyle(rawValue: storedGraphStyle) ?? .rounded }
        set { storedGraphStyle = newValue.rawValue }
    }

    var historyPageSize: Int {
        Self.historyPageSizes.contains(storedHistoryPageSize) ? storedHistoryPageSize : UserDefaultsKey<Int>.historyPageSize.defaultValue
    }

    private let store: UserDefaultsStore
    let workspace: RepositoryWorkspace
    @ObservationIgnored private let loader: Loader
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    @ObservationIgnored private var navigationTask: Task<Void, Never>?
    @ObservationIgnored private var query: (any HistoryQuery)?
    @ObservationIgnored private var cursor: HistoryCursor?
    @ObservationIgnored private var requestID = 0
    @ObservationIgnored private var didRestore = false

    init(store: UserDefaultsStore = .standard, workspace: RepositoryWorkspace = RepositoryWorkspace(), loader: Loader? = nil) {
        self.store = store
        self.workspace = workspace
        self.loader = loader ?? { url, pageSize in try await workspace.history(at: url, pageSize: pageSize) }
    }

    convenience init(defaults: UserDefaults, loader: Loader? = nil) {
        self.init(store: UserDefaultsStore(defaults: defaults), loader: loader)
    }

    isolated deinit {
        loadTask?.cancel()
        pageTask?.cancel()
        navigationTask?.cancel()
        if let query { Task { await query.close() } }
    }

    var selectedRevision: Revision? {
        log?.revisions.first { $0.id == selectedRevisionID }
    }

    var displayedOperationID: String? {
        query?.identity.operationID
    }

    var diffRequest: RevisionDiffRequest? {
        guard let repositoryURL = log?.repositoryURL, let selectedRevision, let query else { return nil }
        return RevisionDiffRequest(
            repositoryURL: repositoryURL,
            commitID: selectedRevision.commitID,
            operationID: query.identity.operationID,
            refreshedAt: lastUpdated,
        )
    }

    func restoreIfNeeded() {
        guard !didRestore else { return }
        didRestore = true
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--repository"), arguments.indices.contains(index + 1) {
            open(URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
        } else if let path = lastWorkspacePath {
            open(URL(fileURLWithPath: path, isDirectory: true))
        }
    }

    func open(_ url: URL) {
        let normalized = url.standardizedFileURL
        if repositoryURL != normalized {
            describeTarget = nil
            commandRequest = nil
            commandNotice = nil
            if let query { Task { await query.close() } }
            query = nil
            cursor = nil
            log = nil
            selectedRevisionID = nil
            lastUpdated = nil
        }
        repositoryURL = normalized
        refresh()
    }

    func refreshIfNeeded() {
        guard !isLoading, repositoryURL != nil else { return }
        if let lastUpdated, Date.now.timeIntervalSince(lastUpdated) < 1 { return }
        refresh()
    }

    func refresh(selecting commitID: String? = nil) {
        guard let directory = repositoryURL else { return }
        loadTask?.cancel()
        navigationTask?.cancel()
        pageTask?.cancel()
        pageTask = nil
        isLoadingMore = false
        pageErrorMessage = nil
        requestID += 1
        let request = requestID
        let previousSelection = selectedRevision
        let pageSize = historyPageSize
        let desiredCount = max(pageSize, log?.revisions.count ?? 0)
        let loader = loader
        isLoading = true
        errorMessage = nil
        let started = ContinuousClock.now
        let logger = Self.logger
        logger.debug("Repository refresh started generation=\(request)")

        loadTask = Task { [weak self] in
            var candidate: (any HistoryQuery)?
            do {
                let history = try await loader(directory, pageSize)
                candidate = history
                var revisions: [Revision] = []
                var cursor: HistoryCursor?
                var foundRequestedCommit = false
                repeat {
                    let page = try await history.page(after: cursor)
                    try Task.checkCancellation()
                    revisions.append(contentsOf: page.revisions)
                    if let commitID, page.revisions.contains(where: { $0.id == commitID }) {
                        foundRequestedCommit = true
                    }
                    cursor = page.nextCursor
                } while cursor != nil && (revisions.count < desiredCount || (commitID != nil && !foundRequestedCommit))
                let log = try await Self.makeLog(identity: history.identity, revisions: revisions, hasMore: cursor != nil)
                try Task.checkCancellation()
                guard let self, requestID == request else {
                    await history.close()
                    return
                }
                let previous = query
                query = history
                self.cursor = cursor
                self.log = log
                repositoryURL = log.repositoryURL
                lastUpdated = .now
                isLoading = false
                loadTask = nil
                remember(log.repositoryURL)
                logger.info("Repository refreshed generation=\(request) revisionCount=\(log.revisions.count) duration=\(String(describing: started.duration(to: .now)), privacy: .public)")
                if let previous { Task { await previous.close() } }

                if let commitID {
                    if foundRequestedCommit {
                        selectedRevisionID = commitID
                        return
                    }
                    commandNotice = String(localized: I18n.historyResultMissing)
                }
                if let selected = selectedRevisionID, log.revisions.contains(where: { $0.id == selected }) { return }
                // Preserve a rewritten change only if the mapping is unambiguous.
                if let previousSelection {
                    let matches = log.revisions.filter { $0.changeID == previousSelection.changeID }
                    if matches.count == 1 {
                        selectedRevisionID = matches[0].id
                        return
                    }
                }
                selectedRevisionID = log.revisions.first(where: \.isWorkingCopy)?.id ?? log.revisions.first?.id
            } catch {
                await candidate?.close()
                guard !Task.isCancelled, let self, requestID == request else { return }
                isLoading = false
                loadTask = nil
                errorMessage = error.localizedDescription
                Self.logger.error("Repository refresh failed: \(String(reflecting: type(of: error)), privacy: .public)")
            }
        }
    }

    func loadMore(retry: Bool = false) {
        guard !isLoading, !isLoadingMore, retry || pageErrorMessage == nil,
              let query, let cursor else { return }
        let request = requestID
        isLoadingMore = true
        pageErrorMessage = nil
        pageTask = Task { [weak self] in
            do {
                let page = try await query.page(after: cursor)
                try Task.checkCancellation()
                guard let self, requestID == request else { return }
                try log?.graph.append(page.revisions)
                log?.revisions.append(contentsOf: page.revisions)
                log?.hasMore = page.nextCursor != nil
                self.cursor = page.nextCursor
                isLoadingMore = false
                pageTask = nil
            } catch {
                guard !Task.isCancelled, let self, requestID == request else { return }
                isLoadingMore = false
                pageTask = nil
                pageErrorMessage = error.localizedDescription
            }
        }
    }

    @concurrent
    private static func makeLog(identity: HistoryIdentity, revisions: [Revision], hasMore: Bool) async throws -> RepositoryLog {
        try RepositoryLog(
            repositoryURL: identity.repositoryURL,
            localBookmarks: identity.localBookmarks,
            operationID: identity.operationID,
            revisions: revisions,
            graph: LogGraph(revisions: revisions),
            hasMore: hasMore,
            backendVersion: identity.backendVersion,
        )
    }

    func setHistoryPageSize(_ size: Int) {
        guard Self.historyPageSizes.contains(size) else { return }
        storedHistoryPageSize = size
    }

    func selectWorkingCopy() {
        locate { $0.isWorkingCopy }
    }

    func selectCommit(_ id: String) {
        locate { $0.id == id }
    }

    func openBookmark(_ name: String, commitID: String, move: Bool) {
        guard let snapshot = log?.snapshotID else { return }
        navigationTask?.cancel()
        navigationTask = Task {
            repeat {
                guard let log, !Task.isCancelled, log.snapshotID == snapshot else { return }
                if let revision = log.revisions.first(where: { $0.id == commitID }) {
                    let row = log.target(for: revision)
                    commandRequest = move ? .moveBookmark(row, name) : .deleteBookmark(row, name)
                    return
                }
            } while await loadNextPage(in: snapshot)
        }
    }

    private func locate(_ matches: @escaping (Revision) -> Bool) {
        navigationTask?.cancel()
        guard let log else { return }
        if let revision = log.revisions.first(where: matches) {
            selectedRevisionID = revision.id
            return
        }
        let snapshotID = log.snapshotID
        navigationTask = Task { [weak self] in
            while let self, await loadNextPage(in: snapshotID) {
                if let revision = self.log?.revisions.first(where: matches) {
                    selectedRevisionID = revision.id
                    return
                }
            }
        }
    }

    func loadNextPage(in snapshotID: UUID) async -> Bool {
        guard !Task.isCancelled, log?.snapshotID == snapshotID, log?.hasMore == true,
              !isLoading, pageErrorMessage == nil else { return false }
        loadMore()
        guard let pageTask else { return false }
        await pageTask.value
        return !Task.isCancelled && log?.snapshotID == snapshotID && pageErrorMessage == nil
    }

    func forget(_ path: String) {
        recentPaths.removeAll { $0 == path }
        if lastWorkspacePath == path {
            lastWorkspacePath = nil
        }
    }

    func beginDescribe(_ target: HistoryRevision) {
        guard target.repositoryURL == repositoryURL, !isSubmitting else { return }
        if target.revision.isImmutable {
            commandNotice = String(localized: I18n.historyImmutableReason(target.revision.shortChangeID))
        } else {
            describeTarget = target
        }
    }

    func submitDescription(
        _ draft: RevisionDescriptionDraft,
        for target: HistoryRevision,
        using submit: (HistoryRevision, RevisionDescriptionDraft) async -> HistoryWriteFeedback,
    ) async {
        guard describeTarget == target, !isSubmitting else { return }
        isSubmitting = true
        describeTarget = nil
        let feedback = await submit(target, draft)
        isSubmitting = false
        guard repositoryURL == target.repositoryURL else { return }
        apply(feedback)
    }

    func run(_ command: RevisionGraphCommand, on target: HistoryRevision) async {
        guard repositoryURL == target.repositoryURL, !isSubmitting else { return }
        commandRequest = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let receipt = try await workspace.apply(command, to: target.writeTarget)
            guard repositoryURL == target.repositoryURL else { return }
            apply(HistoryWriteFeedback(receipt))
        } catch {
            if repositoryURL == target.repositoryURL { commandNotice = error.localizedDescription }
        }
    }

    func loadRemainingPages(in snapshotID: UUID) async {
        while await loadNextPage(in: snapshotID) {}
    }

    private func apply(_ feedback: HistoryWriteFeedback) {
        commandNotice = feedback.message
        if feedback.needsRefresh {
            refresh(selecting: feedback.commitID)
        }
    }

    private func remember(_ url: URL) {
        var paths = recentPaths
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        recentPaths = Array(paths.prefix(12))
        lastWorkspacePath = url.path
    }
}
