// Created by weixi on 2026/09/09.

import Foundation
import Observation

@MainActor
@Observable
final class DiffSession {
    typealias Loader = @Sendable (RevisionDiffRequest) async throws -> RevisionDiff
    typealias FileLoader = @Sendable (RevisionDiffRequest, ChangedFile) async throws -> FileDiff

    private(set) var diff: RevisionDiff?
    private(set) var fileDiff: FileDiff?
    private(set) var selectedFileID: String?
    private(set) var isLoading = false
    private(set) var isLoadingFile = false
    private(set) var errorMessage: String?
    private(set) var fileErrorMessage: String?

    @ObservationIgnored private let loader: Loader
    @ObservationIgnored private let fileLoader: FileLoader
    @ObservationIgnored private var request: RevisionDiffRequest?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var fileTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var fileGeneration = 0

    init(loader: @escaping Loader, fileLoader: @escaping FileLoader) {
        self.loader = loader
        self.fileLoader = fileLoader
    }

    isolated deinit {
        loadTask?.cancel()
        fileTask?.cancel()
    }

    var selectedFile: ChangedFile? { diff?.files.first { $0.id == selectedFileID } }

    func selectRevision(_ request: RevisionDiffRequest?) {
        guard self.request != request else { return }
        // A commit's contents are immutable. A log refresh with the same commit
        // should preserve the reader's file selection, text selection and scroll.
        if let previous = self.request, let request,
           previous.repositoryURL == request.repositoryURL,
           previous.commitID == request.commitID,
           diff != nil, errorMessage == nil, fileErrorMessage == nil {
            self.request = request
            return
        }
        let previousPath = self.request?.repositoryURL == request?.repositoryURL
            && self.request?.commitID == request?.commitID ? selectedFileID : nil
        self.request = request
        loadTask?.cancel()
        loadTask = nil
        generation += 1
        let currentGeneration = generation
        diff = nil
        errorMessage = nil
        selectFile(nil)
        isLoading = request != nil
        guard let request else { return }
        let loader = loader
        loadTask = Task { [weak self] in
            do {
                let diff = try await loader(request)
                try Task.checkCancellation()
                guard let self, self.generation == currentGeneration else { return }
                self.diff = diff
                self.isLoading = false
                self.loadTask = nil
                self.selectFile(diff.files.first(where: { $0.id == previousPath })?.id ?? diff.files.first?.id)
            } catch {
                guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
                self.isLoading = false
                self.loadTask = nil
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func selectFile(_ id: String?) {
        fileTask?.cancel()
        fileTask = nil
        fileGeneration += 1
        let currentGeneration = fileGeneration
        selectedFileID = id
        fileDiff = nil
        fileErrorMessage = nil
        isLoadingFile = false
        guard let request, let file = selectedFile else { return }
        isLoadingFile = true
        let fileLoader = fileLoader
        fileTask = Task { [weak self] in
            do {
                let content = try await fileLoader(request, file)
                try Task.checkCancellation()
                guard let self, self.fileGeneration == currentGeneration else { return }
                self.fileDiff = content
                self.isLoadingFile = false
                self.fileTask = nil
            } catch {
                guard !Task.isCancelled, let self, self.fileGeneration == currentGeneration else { return }
                self.isLoadingFile = false
                self.fileTask = nil
                self.fileErrorMessage = error.localizedDescription
            }
        }
    }
}
