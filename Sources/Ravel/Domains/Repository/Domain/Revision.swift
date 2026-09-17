// Created by weixi on 2026/09/09.

import Foundation

nonisolated struct Revision: Identifiable, Hashable, Sendable {
    let commitID: String
    let changeID: String
    let parentIDs: [String]
    let description: String
    let author: String
    let email: String
    let timestamp: Date
    let bookmarks: [String]
    let isWorkingCopy: Bool
    let isImmutable: Bool
    let hasConflict: Bool
    let isDivergent: Bool
    let isEmpty: Bool

    var id: String {
        commitID
    }

    var summary: String {
        description.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
            ?? ""
    }

    var shortChangeID: String {
        String(changeID.prefix(8))
    }

    var shortCommitID: String {
        String(commitID.prefix(8))
    }
}
