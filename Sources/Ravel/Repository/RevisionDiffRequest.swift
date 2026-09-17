// Created by weixi on 2026/09/17.

import Foundation

nonisolated struct RevisionDiffRequest: Hashable, Sendable {
    let repositoryURL: URL
    let commitID: String
    let operationID: String
    var refreshedAt: Date?
}
