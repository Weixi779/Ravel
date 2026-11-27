//
//  RevisionPresentation.swift
//  Ravel
//
//  Created by weixi on 2026/09/12.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
import Localization

nonisolated extension Revision {
    var rewriteRestriction: LocalizedStringResource? {
        guard isImmutable else { return nil }
        return parentIDs.isEmpty ? I18n.historyRootReason : I18n.historyImmutableReason(shortChangeID)
    }

    var displaySummary: String {
        summary.isEmpty ? String(localized: I18n.commonNoDescription) : summary
    }
}
