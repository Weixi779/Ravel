//
//  RepositoryLog.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation

nonisolated struct RepositoryLog: Sendable {
    let repositoryURL: URL
    let snapshotID = UUID()
    var revisions: [Revision]
    var graph: LogGraph
    var hasMore: Bool
    let backendVersion: String
}
