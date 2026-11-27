//
//  RepositoryLog.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation

nonisolated struct RepositoryLog: Sendable {
    let repositoryURL: URL
    var backingRepositoryURL: URL?
    var localBookmarks: [LocalBookmark] = []
    let operationID: String
    let snapshotID = UUID()
    var revisions: [Revision]
    var graph: LogGraph
    var hasMore: Bool
    let backendVersion: String
}
