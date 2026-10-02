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
    func collapsingSearchResultsDoesNotChangeNormalExpansion() {
        let model = RevisionFileListViewModel()
        model.update(files: [RevisionFilePresentation(ChangedFile(path: "App/Cell.swift", sourcePath: "App/Cell.swift", status: .modified))])
        model.searchText = "Cell"
        _ = model.collapse(.file("App/Cell.swift"), mode: .tree)
        #expect(model.isCollapsed("directory:App", mode: .tree))
        model.searchText = ""
        #expect(!model.isCollapsed("directory:App", mode: .tree))
    }

    @Test
    func searchFindsRenamedSourceAndOpensAncestorsWithoutLosingCollapseState() {
        let files = [
            RevisionFilePresentation(ChangedFile(path: "Sources/New.swift", sourcePath: "Legacy/Old.swift", status: .renamed)),
            RevisionFilePresentation(ChangedFile(path: "Tests/Other.swift", sourcePath: "Tests/Other.swift", status: .added)),
        ]
        let model = RevisionFileListViewModel()
        model.update(files: files)
        model.collapseAll(mode: .tree)
        #expect(model.visibleNodes(mode: .tree).count == 2)
        model.searchText = "old.swift"
        let matches = model.visibleNodes(mode: .tree)
        #expect(matches.compactMap(\.node.file).map(\.path) == ["Sources/New.swift"])
        #expect(model.visibleNodes(mode: .list).count == 1)
        model.searchText = ""
        #expect(model.visibleNodes(mode: .tree).count == 2)
        model.reveal("Sources/New.swift")
        #expect(model.visibleNodes(mode: .tree).count == 3)
    }

    @Test
    func summaryKeepsConflictSeparateFromChangeKindAndBinaryCountsUnknown() {
        let files = [
            RevisionFilePresentation(ChangedFile(path: "a", sourcePath: "a", status: .modified,
                                                 after: FileMetadata(kind: .conflict, executable: nil, conflictSides: 2))),
            RevisionFilePresentation(ChangedFile(path: "new", sourcePath: "old", status: .renamed)),
        ]
        let summary = RevisionChangeSummary(files: files, statistics: nil)
        #expect(summary.statusCounts[.modified] == 1)
        #expect(summary.statusCounts[.renamed] == 1)
        #expect(summary.conflicts == 1)
        #expect(summary.additions == nil && summary.deletions == nil)
        let binary = RevisionLineStatistics(.init(additions: nil, deletions: nil, bytesDelta: 8))
        #expect(binary.isBinary)
    }

    @Test
    func previewCacheEvictsByCostAndSeparatesRepositoryAndOperation() throws {
        let diff = try RevisionPatchParser.parse("@@ -0,0 +1,1 @@\n+sample\n")
        let content = RevisionDiffPresentation(diff, fileName: "sample.swift")
        let cache = RevisionPreviewCache(byteLimit: content.estimatedBytes * 2)
        let revision = RevisionPreviewCache.Key(.init(repositoryURL: URL(fileURLWithPath: "/repo"), commitID: "a", operationID: "op"))
        let a = RevisionPreviewCache.FileKey(revision: revision, path: "a")
        let b = RevisionPreviewCache.FileKey(revision: revision, path: "b")
        let c = RevisionPreviewCache.FileKey(revision: revision, path: "c")
        cache.store(content, for: a)
        cache.store(content, for: b)
        #expect(cache.content(a) != nil)
        cache.store(content, for: c)
        #expect(cache.content(b) == nil)
        #expect(cache.content(a) != nil && cache.content(c) != nil)
        let otherOperation = RevisionPreviewCache.Key(.init(repositoryURL: URL(fileURLWithPath: "/repo"), commitID: "a", operationID: "other"))
        #expect(cache.content(.init(revision: otherOperation, path: "a")) == nil)
        cache.clear()
        #expect(cache.content(a) == nil)
    }
}
