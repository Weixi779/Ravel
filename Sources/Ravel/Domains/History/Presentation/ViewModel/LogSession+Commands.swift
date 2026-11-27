//
//  LogSession+Commands.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
import Localization

extension HistoryRevision {
    var writeTarget: RevisionWriteTarget {
        RevisionWriteTarget(workspaceURL: repositoryURL, operationID: operationID, commitID: revision.commitID, changeID: revision.changeID)
    }
}

extension LogSession {
    func saveDescription(_ draft: RevisionDescriptionDraft, for target: HistoryRevision) async {
        await submitDescription(draft, for: target) { target, draft in
            do {
                return try await HistoryWriteFeedback(workspace.describe(target.writeTarget, title: draft.title, body: draft.body))
            } catch {
                return HistoryWriteFeedback(commitID: nil, needsRefresh: false, message: error.localizedDescription)
            }
        }
    }
}

extension HistoryWriteFeedback {
    init(_ receipt: RepositoryWriteReceipt) {
        let committed = receipt.mutationOperationID != nil
        let prepared = receipt.preparationOperationID != nil
        let detail = receipt.detail ?? ""
        switch receipt.disposition {
        case .succeeded:
            self.init(commitID: receipt.commitID, needsRefresh: true, message: nil)
        case .committedWithSyncFailure:
            let phase = receipt.git == .failed ? I18n.historyGitSyncFailure : I18n.historyWorkspaceSyncFailure
            self.init(commitID: committed ? receipt.commitID : nil, needsRefresh: true, message: String(localized: phase) + "\n" + detail)
        case .outcomeUnknown:
            self.init(commitID: nil, needsRefresh: true, message: String(localized: I18n.historyUnknownOutcome) + "\n" + detail)
        default:
            let message = prepared ? String(localized: I18n.historyPreparedOnly) + "\n" + detail : detail
            self.init(commitID: nil, needsRefresh: prepared || receipt.disposition == .staleTarget, message: message)
        }
    }
}
