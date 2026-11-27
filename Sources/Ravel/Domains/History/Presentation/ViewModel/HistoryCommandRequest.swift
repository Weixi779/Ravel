//
//  HistoryCommandRequest.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
import Localization

enum HistoryCommandRequest: Identifiable, Hashable {
    case find
    case rebase(HistoryRevision)
    case createBookmark(HistoryRevision)
    case moveBookmark(HistoryRevision, String)
    case deleteBookmark(HistoryRevision, String)

    var id: Self { self }

    var source: HistoryRevision? {
        switch self {
        case .find: nil
        case let .rebase(row), let .createBookmark(row), let .moveBookmark(row, _), let .deleteBookmark(row, _): row
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .find: I18n.historyFind
        case .rebase: I18n.historyRebase
        case .createBookmark: I18n.historyCreateBookmark
        case .moveBookmark: I18n.historyMoveBookmark
        case .deleteBookmark: I18n.historyDeleteBookmark
        }
    }

    var needsPicker: Bool {
        switch self {
        case .find, .rebase, .moveBookmark: true
        default: false
        }
    }
}

extension RepositoryLog {
    func target(for revision: Revision) -> HistoryRevision {
        HistoryRevision(repositoryURL: repositoryURL, operationID: operationID, revision: revision)
    }

    // History pages arrive in reverse topological order. All descendants of
    // a loaded source necessarily precede it, even when more ancestors remain.
    func descendantIDs(of source: Revision) -> Set<String> {
        var related = Set([source.id])
        for revision in revisions.prefix(while: { $0.id != source.id }).reversed()
            where revision.parentIDs.contains(where: related.contains) {
            related.insert(revision.id)
        }
        related.remove(source.id)
        return related
    }
}
