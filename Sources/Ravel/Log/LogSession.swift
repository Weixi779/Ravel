// Created by weixi on 2026/09/09.

import Foundation
import Observation

@MainActor
@Observable
final class LogSession {
    typealias Loader = @Sendable (URL, String?) async throws -> RepositoryLog

    private(set) var repositoryURL: URL?
    private(set) var log: RepositoryLog?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var recentPaths: [String]
    private(set) var lastUpdated: Date?
    var selectedRevisionID: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loader: Loader
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var requestID = 0
    @ObservationIgnored private var didRestore = false

    init(defaults: UserDefaults = .standard, loader: @escaping Loader = JJClient.loadLog) {
        self.defaults = defaults
        self.loader = loader
        self.recentPaths = defaults.stringArray(forKey: "recentRepositoryPaths") ?? []
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
            executablePath: defaults.string(forKey: "jjExecutablePath"),
            refreshedAt: lastUpdated
        )
    }

    func restoreIfNeeded() {
        guard !didRestore else { return }
        didRestore = true
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--repository"), arguments.indices.contains(index + 1) {
            open(URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
        } else if let path = defaults.string(forKey: "lastRepositoryPath") {
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
        let executable = defaults.string(forKey: "jjExecutablePath")
        let loader = loader
        isLoading = true
        errorMessage = nil

        loadTask = Task { [weak self] in
            do {
                let log = try await loader(directory, executable)
                try Task.checkCancellation()
                guard let self, self.requestID == request else { return }
                self.log = log
                self.repositoryURL = log.repositoryURL
                self.lastUpdated = .now
                self.isLoading = false
                self.loadTask = nil
                self.remember(log.repositoryURL)

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
                guard !Task.isCancelled, let self, self.requestID == request else { return }
                self.isLoading = false
                self.loadTask = nil
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func setExecutable(_ url: URL) {
        defaults.set(url.path, forKey: "jjExecutablePath")
        refresh()
    }

    func selectWorkingCopy() {
        selectedRevisionID = log?.revisions.first(where: \.isWorkingCopy)?.id
    }

    func forget(_ path: String) {
        recentPaths.removeAll { $0 == path }
        defaults.set(recentPaths, forKey: "recentRepositoryPaths")
        if defaults.string(forKey: "lastRepositoryPath") == path {
            defaults.removeObject(forKey: "lastRepositoryPath")
        }
    }

    private func remember(_ url: URL) {
        recentPaths.removeAll { $0 == url.path }
        recentPaths.insert(url.path, at: 0)
        recentPaths = Array(recentPaths.prefix(12))
        defaults.set(recentPaths, forKey: "recentRepositoryPaths")
        defaults.set(url.path, forKey: "lastRepositoryPath")
    }
}
