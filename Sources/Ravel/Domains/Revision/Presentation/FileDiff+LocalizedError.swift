//
//  FileDiff+LocalizedError.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Localization

nonisolated extension FileDiff.Failure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .malformedPatch: String(localized: I18n.errorsMalformedPatch)
        case .tooLarge: String(localized: I18n.errorsDiffTooLarge)
        }
    }
}
