//
//  RevisionChangesSession.swift
//  Ravel
//
//  Created by weixi on 2026/09/09.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Observation

@MainActor
@Observable
final class RevisionChangesSession {
    typealias Loader = @Sendable (RevisionDiffRequest) async throws -> RevisionDiff
    typealias FileLoader = @Sendable (RevisionDiffRequest, ChangedFile) async throws -> FileDiff
    typealias StatisticsLoader = @Sendable (RevisionDiffRequest) async throws -> RevisionDiffStatistics?

    private(set) var files: [RevisionFilePresentation] = []
    private(set) var summary = RevisionChangeSummary(files: [], statistics: nil)
    private(set) var fileDiff: RevisionDiffPresentation?
    private(set) var selectedFileID: String?
    private(set) var displayedFile: RevisionFilePresentation?
    private(set) var displayedTitle = ""
    private(set) var displayedChangeID = ""
    private(set) var isLoading = false
    private(set) var isLoadingFile = false
    private(set) var showsRevisionProgress = false
    private(set) var showsFileProgress = false
    private(set) var errorMessage: String?
    private(set) var fileErrorMessage: String?
    private(set) var statisticsErrorMessage: String?
    let fileList = RevisionFileListViewModel()
    var showsDetails = false
    var showsFileInformation = false
    var findRequest = 0

    @ObservationIgnored private(set) var diff: RevisionDiff?
    @ObservationIgnored private let loader: Loader
    @ObservationIgnored private let fileLoader: FileLoader
    @ObservationIgnored private let statisticsLoader: StatisticsLoader
    @ObservationIgnored private let loadingDelay: Duration
    @ObservationIgnored private let cache = RevisionPreviewCache()
    @ObservationIgnored private var request: RevisionDiffRequest?
    @ObservationIgnored private var displayedRequest: RevisionDiffRequest?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var fileTask: Task<Void, Never>?
    @ObservationIgnored private var statisticsTask: Task<Void, Never>?
    @ObservationIgnored private var preloadTask: Task<Void, Never>?
    @ObservationIgnored private var revisionProgressTask: Task<Void, Never>?
    @ObservationIgnored private var fileProgressTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var fileGeneration = 0

    init(loader: @escaping Loader, fileLoader: @escaping FileLoader,
         statisticsLoader: @escaping StatisticsLoader = { _ in nil }, loadingDelay: Duration = .milliseconds(250))
    {
        self.loader = loader
        self.fileLoader = fileLoader
        self.statisticsLoader = statisticsLoader
        self.loadingDelay = loadingDelay
    }

    isolated deinit { cancelTasks() }

    func selectRevision(_ request: RevisionDiffRequest?, revision: Revision? = nil) {
        guard self.request != request else { return }
        if let previous = self.request, let request,
           previous.repositoryURL == request.repositoryURL,
           previous.commitID == request.commitID,
           displayedRequest?.commitID == request.commitID,
           !isLoading, errorMessage == nil, fileErrorMessage == nil
        {
            self.request = request
            displayedRequest = request
            if summary.additions == nil { loadStatistics(request, generation: generation) }
            return
        }
        let previousRepository = self.request?.repositoryURL
        cancelTasks()
        generation += 1
        fileGeneration += 1
        self.request = request
        isLoading = false
        isLoadingFile = false
        showsRevisionProgress = false
        showsFileProgress = false
        errorMessage = nil
        statisticsErrorMessage = nil
        guard let request else {
            clearPresentation()
            cache.clear()
            return
        }
        if previousRepository != request.repositoryURL {
            clearPresentation()
            cache.clear()
        }
        let key = RevisionPreviewCache.Key(request)
        let title = revision?.displaySummary ?? String(request.commitID.prefix(12))
        let changeID = revision?.shortChangeID ?? String(request.commitID.prefix(8))
        let currentGeneration = generation
        if let cached = cache.revision(key) {
            let first = cached.files.first { $0.id == cache.selection(key) } ?? cached.files.first
            let content = first.flatMap { cache.content(.init(revision: key, path: $0.path)) }
            if first == nil || content != nil {
                publish(cached, request: request, file: first, content: content, error: nil, title: title, changeID: changeID)
                loadStatistics(request, generation: currentGeneration)
                return
            }
        }
        isLoading = true
        revisionProgressTask = delayedProgress(forFile: false)
        loadStatistics(request, generation: currentGeneration)
        let loader = loader
        let fileLoader = fileLoader
        let cachedRevision = cache.revision(key)
        let preferredPath = cache.selection(key)
        loadTask = Task { [weak self] in
            do {
                let result: RevisionDiff = if let cachedRevision { cachedRevision }
                else { try await loader(request) }
                try Task.checkCancellation()
                let first = result.files.first { $0.id == preferredPath } ?? result.files.first
                var content: RevisionDiffPresentation?
                var fileError: String?
                if let first {
                    content = self?.cache.content(.init(revision: key, path: first.path))
                    if content == nil {
                        do {
                            content = try await Self.loadPresentation(request, file: first, using: fileLoader)
                        } catch {
                            try Task.checkCancellation()
                            fileError = error.localizedDescription
                        }
                    }
                }
                try Task.checkCancellation()
                guard let self, generation == currentGeneration else { return }
                publish(result, request: request, file: first, content: content, error: fileError, title: title, changeID: changeID)
                finishRevisionLoading()
                preloadNextFile(after: first, request: request)
            } catch {
                guard !Task.isCancelled, let self, generation == currentGeneration else { return }
                clearPresentation()
                displayedTitle = title
                displayedChangeID = changeID
                errorMessage = error.localizedDescription
                finishRevisionLoading()
            }
        }
    }

    func selectFile(_ id: String?) {
        guard !isLoading, let request = displayedRequest, let file = diff?.files.first(where: { $0.id == id }) else { return }
        guard selectedFileID != id || fileErrorMessage != nil else { return }
        fileTask?.cancel()
        preloadTask?.cancel()
        fileProgressTask?.cancel()
        fileGeneration += 1
        let currentGeneration = fileGeneration
        selectedFileID = id
        showsFileProgress = false
        fileErrorMessage = nil
        let key = RevisionPreviewCache.FileKey(revision: .init(request), path: file.path)
        cache.select(file.id, in: key.revision)
        if let cached = cache.content(key) {
            publishFile(file, content: cached, error: nil)
            isLoadingFile = false
            preloadNextFile(after: file, request: request)
            return
        }
        isLoadingFile = true
        fileProgressTask = delayedProgress(forFile: true)
        let fileLoader = fileLoader
        fileTask = Task { [weak self] in
            do {
                let content = try await Self.loadPresentation(request, file: file, using: fileLoader)
                try Task.checkCancellation()
                guard let self, fileGeneration == currentGeneration else { return }
                cache.store(content, for: key)
                publishFile(file, content: content, error: nil)
                finishFileLoading()
                preloadNextFile(after: file, request: request)
            } catch {
                guard !Task.isCancelled, let self, fileGeneration == currentGeneration else { return }
                publishFile(file, content: nil, error: error.localizedDescription)
                finishFileLoading()
            }
        }
    }

    func retryStatistics() {
        guard let request else { return }
        loadStatistics(request, generation: generation)
    }

    private func publish(_ diff: RevisionDiff, request: RevisionDiffRequest, file: ChangedFile?, content: RevisionDiffPresentation?, error: String?, title: String, changeID: String) {
        self.diff = diff
        displayedRequest = request
        displayedTitle = title
        displayedChangeID = changeID
        let key = RevisionPreviewCache.Key(request)
        cache.store(diff, for: key)
        updateStatistics(cache.statistics(key))
        selectedFileID = file?.id
        cache.select(file?.id, in: key)
        if let file {
            if let content { cache.store(content, for: .init(revision: key, path: file.path)) }
            publishFile(file, content: content, error: error)
        } else {
            displayedFile = nil
            fileDiff = nil
            fileErrorMessage = nil
        }
    }

    private func publishFile(_ file: ChangedFile, content: RevisionDiffPresentation?, error: String?) {
        showsFileInformation = false
        displayedFile = files.first { $0.id == file.id }
        fileDiff = content
        fileErrorMessage = error
    }

    private func loadStatistics(_ request: RevisionDiffRequest, generation: Int) {
        statisticsTask?.cancel()
        statisticsErrorMessage = nil
        let key = RevisionPreviewCache.Key(request)
        if let statistics = cache.statistics(key) {
            if displayedRequest.map(RevisionPreviewCache.Key.init) == key { updateStatistics(statistics) }
            return
        }
        let statisticsLoader = statisticsLoader
        statisticsTask = Task { [weak self] in
            do {
                guard let statistics = try await statisticsLoader(request) else { return }
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                cache.store(statistics, for: key)
                if displayedRequest.map(RevisionPreviewCache.Key.init) == key { updateStatistics(statistics) }
            } catch {
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                statisticsErrorMessage = error.localizedDescription
            }
        }
    }

    private func updateStatistics(_ statistics: RevisionDiffStatistics?) {
        files = (diff?.files ?? []).map { RevisionFilePresentation($0, statistics: statistics?.files[$0.path]) }
        summary = RevisionChangeSummary(files: files, statistics: statistics)
        fileList.update(files: files)
        if let displayedFile { self.displayedFile = files.first { $0.id == displayedFile.id } }
    }

    private func preloadNextFile(after file: ChangedFile?, request: RevisionDiffRequest) {
        preloadTask?.cancel()
        guard let file, let files = diff?.files, let index = files.firstIndex(where: { $0.id == file.id }),
              files.indices.contains(index + 1) else { return }
        let next = files[index + 1]
        let key = RevisionPreviewCache.FileKey(revision: .init(request), path: next.path)
        guard cache.content(key) == nil else { return }
        let fileLoader = fileLoader
        preloadTask = Task(priority: .utility) { [weak self] in
            // Let visible work settle first. Rapid navigation cancels this before it starts.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            guard let content = try? await Self.loadPresentation(request, file: next, using: fileLoader),
                  !Task.isCancelled, let self, self.request.map(RevisionPreviewCache.Key.init) == key.revision else { return }
            cache.store(content, for: key)
        }
    }

    @concurrent
    private static func loadPresentation(_ request: RevisionDiffRequest, file: ChangedFile, using loader: FileLoader) async throws -> RevisionDiffPresentation {
        let content = try await loader(request, file)
        try Task.checkCancellation()
        return RevisionDiffPresentation(content, fileName: (file.path as NSString).lastPathComponent)
    }

    private func delayedProgress(forFile: Bool) -> Task<Void, Never> {
        let delay = loadingDelay
        return Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            if forFile { showsFileProgress = isLoadingFile }
            else { showsRevisionProgress = isLoading }
        }
    }

    private func finishRevisionLoading() {
        isLoading = false
        showsRevisionProgress = false
        revisionProgressTask?.cancel()
        loadTask = nil
    }

    private func finishFileLoading() {
        isLoadingFile = false
        showsFileProgress = false
        fileProgressTask?.cancel()
        fileTask = nil
    }

    private func clearPresentation() {
        diff = nil
        files = []
        fileList.update(files: [])
        summary = RevisionChangeSummary(files: [], statistics: nil)
        fileDiff = nil
        displayedFile = nil
        selectedFileID = nil
        displayedRequest = nil
        displayedTitle = ""
        displayedChangeID = ""
        fileErrorMessage = nil
    }

    private func cancelTasks() {
        loadTask?.cancel()
        fileTask?.cancel()
        statisticsTask?.cancel()
        preloadTask?.cancel()
        revisionProgressTask?.cancel()
        fileProgressTask?.cancel()
    }
}
