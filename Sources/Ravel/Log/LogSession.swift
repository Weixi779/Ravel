// Created by weixi on 2026/09/09.

import Foundation
import Logger
import Observation
import UserDefaultsKit
import UserDefaultsKitMacros

@MainActor
@Observable
final class LogSession {
    private static let logger = Logger.make(category: "Repository")
    typealias Loader = @Sendable (URL, String?) async throws -> RepositoryLog

    private(set) var repositoryURL: URL?
    private(set) var log: RepositoryLog?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    @ObservedDefault(.recentWorkspacePaths, store: \Self.store)
    @ObservationIgnored
    private(set) var recentPaths: [String]
    private(set) var lastUpdated: Date?
    var selectedRevisionID: String?

    @ObservedDefault(.lastWorkspacePath, store: \Self.store)
    @ObservationIgnored
    private var lastWorkspacePath: String?

    @ObservedDefault(.jjExecutablePath, store: \Self.store)
    @ObservationIgnored
    private var jjExecutablePath: String?

    private let store: UserDefaultsStore
    @ObservationIgnored private let loader: Loader
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var requestID = 0
    @ObservationIgnored private var didRestore = false

    init(store: UserDefaultsStore = .standard, loader: @escaping Loader = JJClient.loadLog) {
        self.store = store
        self.loader = loader
    }

    convenience init(defaults: UserDefaults, loader: @escaping Loader = JJClient.loadLog) {
        self.init(store: UserDefaultsStore(defaults: defaults), loader: loader)
    }

    isolated deinit {
        loadTask?.cancel()
    }

    var selectedRevision: Revision? {
        log?.revisions.first { $0.id == selectedRevisionID }
    }

    var diffRequest: DiffSession.Request? {
        guard let repositoryURL = log?.repositoryURL, let selectedRevision else { return nil }
        return DiffSession.Request(
            repositoryURL: repositoryURL,
            commitID: selectedRevision.commitID,
            executablePath: jjExecutablePath,
            refreshedAt: lastUpdated
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

    func refresh() {
        guard let directory = repositoryURL else { return }
        loadTask?.cancel()
        requestID += 1
        let request = requestID
        let previousSelection = selectedRevision
        let executable = jjExecutablePath
        let loader = loader
        isLoading = true
        errorMessage = nil
        let logger = Self.logger
        let operationID = UUID().uuidString
        let started = ContinuousClock.now
        logger.debug("Repository refresh started requestID=\(operationID, privacy: .public)")

        loadTask = Task { [weak self] in
            do {
                let log = try await loader(directory, executable)
                try Task.checkCancellation()
                guard let self, self.requestID == request else {
                    logger.debug("Repository refresh superseded requestID=\(operationID, privacy: .public)")
                    return
                }
                self.log = log
                self.repositoryURL = log.repositoryURL
                self.lastUpdated = .now
                self.isLoading = false
                self.loadTask = nil
                self.remember(log.repositoryURL)
                logger.info("""
                    Repository refreshed requestID=\(operationID, privacy: .public) revisionCount=\(log.revisions.count) \
                    duration=\(String(describing: started.duration(to: .now)), privacy: .public)
                    """)

                if let selected = self.selectedRevisionID, log.revisions.contains(where: { $0.id == selected }) {
                    return
                }
                // Preserve a rewritten change only if the mapping is unambiguous.
                if let previousSelection {
                    let matches = log.revisions.filter { $0.changeID == previousSelection.changeID }
                    if matches.count == 1 {
                        self.selectedRevisionID = matches[0].id
                        return
                    }
                }
                self.selectedRevisionID = log.revisions.first(where: \.isWorkingCopy)?.id ?? log.revisions.first?.id
            } catch {
                guard !Task.isCancelled, let self, self.requestID == request else {
                    logger.debug("Repository refresh cancelled or superseded requestID=\(operationID, privacy: .public)")
                    return
                }
                self.isLoading = false
                self.loadTask = nil
                self.errorMessage = error.localizedDescription
                logger.error("""
                    Repository refresh failed requestID=\(operationID, privacy: .public) \
                    errorType=\(String(reflecting: type(of: error)), privacy: .public) \
                    duration=\(String(describing: started.duration(to: .now)), privacy: .public)
                    """)
            }
        }
    }

    func setExecutable(_ url: URL) {
        jjExecutablePath = url.path
        refresh()
    }

    func selectWorkingCopy() {
        selectedRevisionID = log?.revisions.first(where: \.isWorkingCopy)?.id
    }

    func forget(_ path: String) {
        recentPaths.removeAll { $0 == path }
        if lastWorkspacePath == path {
            lastWorkspacePath = nil
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
