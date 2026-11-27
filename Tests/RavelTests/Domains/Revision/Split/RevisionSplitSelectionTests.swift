//
//  RevisionSplitSelectionTests.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit
@testable import Ravel
import Testing

@MainActor
struct RevisionSplitSelectionTests {
    @Test
    func hunkOwnershipSurvivesChangingDiffLayout() throws {
        let selection = RevisionSplitPreviewData.selection()
        let path = RevisionSplitPreviewData.file.path
        let presentation = RevisionSplitPreviewData.presentation
        let ranges = presentation.hunks.map(\.range)
        #expect(ranges.count == 2)
        let first = try #require(ranges.first)
        let second = try #require(ranges.last)
        #expect(presentation.before.rows.contains { $0.line.kind == .spacer })
        #expect(presentation.after.rows.contains { $0.line.newNumber == 21 })
        #expect(presentation.unified.rows.count != presentation.before.rows.count)

        let view = RevisionDiffContainerView()
        for sideBySide in [false, true, false] {
            view.frame.size = sideBySide ? NSSize(width: 480, height: 240) : NSSize(width: 900, height: 300)
            view.update(presentation, sideBySide: sideBySide, showsChangeMarkers: sideBySide, findRequest: 0)
            view.layoutSubtreeIfNeeded()
            #expect(selection.first == [path: .hunks([first])])
            #expect(!selection.includes(second, in: path))
            #expect(selection.canSplit)
        }
        selection.setFile(path, included: true)
        #expect(!selection.canSplit)
        selection.setHunk(first, included: false, in: path, available: ranges)
        #expect(selection.first[path] == .hunks([second]))
        selection.setHunk(second, included: false, in: path, available: ranges)
        #expect(selection.first.isEmpty)
    }

    @Test
    func sessionCapturesOnlyDisplayedSourceAndReleasesSelectionOnNavigation() async throws {
        let file = RevisionSplitPreviewData.file
        let session = RevisionChangesSession(loader: { _ in .init(files: [file]) }, fileLoader: { _, _ in
            try RevisionPatchParser.parse("@@ -1 +1 @@\n-old\n+new")
        })
        let source = revision("one")
        let request = RevisionDiffRequest(repositoryURL: URL(fileURLWithPath: "/sample"), commitID: source.id, operationID: "op")
        session.selectRevision(request, revision: source)
        while session.isLoading { await Task.yield() }
        session.beginSplit(revision("other"), request: request)
        #expect(!session.isSelectingSplit)
        session.beginSplit(source, request: request)
        #expect(session.isSelectingSplit)
        session.selectRevision(request, revision: source)
        #expect(session.splitSelection?.source == source)
        session.selectRevision(nil)
        #expect(!session.isSelectingSplit)
    }
}
