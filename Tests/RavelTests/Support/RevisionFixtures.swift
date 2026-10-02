//
//  RevisionFixtures.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation
@testable import Ravel

nonisolated func revision(_ id: String, change: String? = nil, parents: [String] = [], workingCopy: Bool = false) -> Revision {
    Revision(
        commitID: id, changeID: change ?? id, parentIDs: parents, description: "Change \(id)",
        author: "weixi", email: "weixi@example.com", timestamp: Date(timeIntervalSince1970: 1_789_000_000),
        bookmarks: [], isWorkingCopy: workingCopy, isImmutable: false, hasConflict: false,
        isDivergent: false, isEmpty: false,
    )
}

nonisolated func repositoryLog(_ path: String, revisions: [Revision]) throws -> RepositoryLog {
    try RepositoryLog(
        repositoryURL: URL(fileURLWithPath: path, isDirectory: true), revisions: revisions,
        graph: LogGraph(revisions: revisions), hasMore: false, backendVersion: "Test",
    )
}
