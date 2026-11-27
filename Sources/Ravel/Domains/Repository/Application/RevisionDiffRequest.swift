//
//  RevisionDiffRequest.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation

nonisolated struct RevisionDiffRequest: Hashable, Sendable {
    let repositoryURL: URL
    let commitID: String
    let operationID: String
    var refreshedAt: Date?
}
