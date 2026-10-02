//
//  RevisionChangeSummaryTests.swift
//  Ravel
//
//  Created by weixi on 2026/10/02.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
@testable import Ravel
import Testing

@MainActor
struct RevisionChangeSummaryTests {
    @Test
    func summaryKeepsConflictSeparateFromChangeKindAndBinaryCountsUnknown() {
        let files = [
            RevisionFilePresentation(ChangedFile(
                path: "a",
                sourcePath: "a",
                status: .modified,
                after: FileMetadata(kind: .conflict, executable: nil, conflictSides: 2),
            )),
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
}
