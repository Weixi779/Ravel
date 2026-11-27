//
//  RevisionDescriptionDraft.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation

struct RevisionDescriptionDraft: Equatable {
    var title: String
    var body: String

    init(_ description: String) {
        let parts = description.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        title = parts.first.map(String.init) ?? ""
        let remainder = parts.dropFirst().first.map(String.init) ?? ""
        body = remainder.hasPrefix("\n") ? String(remainder.dropFirst()) : remainder
    }
}

struct HistoryRevision: Identifiable, Hashable {
    let repositoryURL: URL
    let operationID: String
    let revision: Revision
    var id: Self { self }
}

struct HistoryWriteFeedback {
    let commitID: String?
    let needsRefresh: Bool
    let message: String?
}
