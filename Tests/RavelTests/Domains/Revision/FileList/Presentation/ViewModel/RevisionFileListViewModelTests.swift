//
//  RevisionFileListViewModelTests.swift
//  Ravel
//
//  Created by weixi on 2026/09/18.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
@testable import Ravel
import Testing

@MainActor
struct RevisionFileListViewModelTests {
    @Test
    func horizontalNavigationKeepsNestedCollapseStateAndTreatsFlatListsAsLeaves() {
        let model = RevisionFileListViewModel()
        model.update(files: [RevisionFilePresentation(ChangedFile(path: "App/UI/Cell.swift", sourcePath: "App/UI/Cell.swift", status: .modified))])
        let file = RevisionFileListViewModel.Selection.file("App/UI/Cell.swift")
        let inner = RevisionFileListViewModel.Selection.directory("directory:App/UI")
        let outer = RevisionFileListViewModel.Selection.directory("directory:App")
        #expect(model.collapse(file, mode: .tree) == inner)
        #expect(model.isCollapsed("directory:App/UI", mode: .tree))
        #expect(model.collapse(inner, mode: .tree) == outer)
        #expect(!model.isCollapsed("directory:App", mode: .tree))
        #expect(model.collapse(outer, mode: .tree) == outer)
        #expect(model.isCollapsed("directory:App", mode: .tree))
        #expect(model.expand(outer, mode: .tree) == outer)
        #expect(model.isCollapsed("directory:App/UI", mode: .tree))
        #expect(model.expand(outer, mode: .tree) == inner)
        #expect(model.expand(inner, mode: .tree) == inner)
        #expect(model.expand(inner, mode: .tree) == file)
        #expect(model.collapse(file, mode: .list) == file)
        #expect(model.expand(file, mode: .list) == file)
    }

    @Test
    func collapsingSearchResultsDoesNotChangeNormalExpansion() async throws {
        let model = RevisionFileListViewModel()
        model.update(files: [RevisionFilePresentation(ChangedFile(path: "App/Cell.swift", sourcePath: "App/Cell.swift", status: .modified))])
        model.searchText = "Cell"
        try await waitUntil { model.appliedSearchText == "Cell" }
        _ = model.collapse(.file("App/Cell.swift"), mode: .tree)
        #expect(model.isCollapsed("directory:App", mode: .tree))
        model.searchText = ""
        #expect(!model.isCollapsed("directory:App", mode: .tree))
    }

    @Test
    func searchFindsRenamedSourceAndOpensAncestorsWithoutLosingCollapseState() async throws {
        let files = [
            RevisionFilePresentation(ChangedFile(path: "Sources/New.swift", sourcePath: "Legacy/Old.swift", status: .renamed)),
            RevisionFilePresentation(ChangedFile(path: "Tests/Other.swift", sourcePath: "Tests/Other.swift", status: .added)),
        ]
        let model = RevisionFileListViewModel()
        model.update(files: files)
        model.collapseAll(mode: .tree)
        #expect(model.visibleNodes(mode: .tree).count == 2)
        model.searchText = "old.swift"
        try await waitUntil { model.appliedSearchText == "old.swift" }
        let matches = model.visibleNodes(mode: .tree)
        #expect(matches.compactMap(\.node.file).map(\.path) == ["Sources/New.swift"])
        #expect(model.visibleNodes(mode: .list).count == 1)
        model.searchText = ""
        #expect(model.visibleNodes(mode: .tree).count == 2)
        model.reveal("Sources/New.swift")
        #expect(model.visibleNodes(mode: .tree).count == 3)
    }

    @Test
    func typingKeepsCurrentResultsUntilTheLatestSearchIsReady() async throws {
        let delay = SearchDelay()
        let model = RevisionFileListViewModel(waitForSearch: delay.wait)
        model.update(files: searchFiles)
        model.collapseAll(mode: .tree)

        model.searchText = "Old"
        #expect(model.searchText == "Old")
        #expect(model.appliedSearchText.isEmpty)
        #expect(model.visibleNodes(mode: .tree).count == 2)
        try await waitUntil { delay.started == 1 }

        model.searchText = "Other"
        try await waitUntil { delay.started == 2 }
        delay.resumeNext()
        try await waitUntil { delay.completed == 1 }
        #expect(model.appliedSearchText.isEmpty)
        #expect(model.visibleNodes(mode: .tree).count == 2)

        delay.resumeNext()
        try await waitUntil { model.appliedSearchText == "Other" }
        #expect(model.visibleNodes(mode: .tree).compactMap(\.node.file).map(\.path) == ["Tests/Other.swift"])
    }

    @Test
    func clearingSearchImmediatelyRestoresFilesAndCancelsPendingInput() async throws {
        let delay = SearchDelay()
        let model = RevisionFileListViewModel(waitForSearch: delay.wait)
        model.update(files: searchFiles)
        model.searchText = "Old"
        try await waitUntil { delay.started == 1 }
        delay.resumeNext()
        try await waitUntil { model.appliedSearchText == "Old" }
        #expect(model.visibleNodes(mode: .list).count == 1)

        model.searchText = "Other"
        try await waitUntil { delay.started == 2 }
        model.searchText = ""
        #expect(model.appliedSearchText.isEmpty)
        #expect(model.visibleNodes(mode: .list).count == 2)

        delay.resumeNext()
        try await waitUntil { delay.completed == 2 }
        #expect(model.appliedSearchText.isEmpty)
        #expect(model.visibleNodes(mode: .list).count == 2)
    }

    @Test
    func pendingSearchDoesNotRetainTheFileList() async throws {
        let delay = SearchDelay()
        var model: RevisionFileListViewModel? = RevisionFileListViewModel(waitForSearch: delay.wait)
        let isReleased = { [weak model] in model == nil }
        model?.searchText = "Cell"
        try await waitUntil { delay.started == 1 }

        model = nil
        #expect(isReleased())
        delay.resumeNext()
        try await waitUntil { delay.completed == 1 }
    }

    private var searchFiles: [RevisionFilePresentation] {
        [
            RevisionFilePresentation(ChangedFile(path: "Sources/New.swift", sourcePath: "Legacy/Old.swift", status: .renamed)),
            RevisionFilePresentation(ChangedFile(path: "Tests/Other.swift", sourcePath: "Tests/Other.swift", status: .added)),
        ]
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(condition(), sourceLocation: sourceLocation)
    }

    @MainActor
    private final class SearchDelay {
        private(set) var started = 0
        private(set) var completed = 0
        private var pending: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            started += 1
            await withCheckedContinuation { pending.append($0) }
            completed += 1
        }

        func resumeNext() {
            pending.removeFirst().resume()
        }
    }
}
