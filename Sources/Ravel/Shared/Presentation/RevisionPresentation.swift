//
//  RevisionPresentation.swift
//  Ravel
//
//  Created by weixi on 2026/09/12.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Localization

nonisolated extension Revision {
    var displaySummary: String {
        summary.isEmpty ? String(localized: I18n.commonNoDescription) : summary
    }
}
