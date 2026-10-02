//
//  ChangedFileStatus+Presentation.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import DesignSystem
import SwiftUI

extension RevisionFilePresentation.Status {
    var tone: ChangeTone {
        switch self {
        case .added: .addition
        case .removed: .deletion
        case .modified, .unchanged: .modification
        case .copied, .renamed: .movement
        }
    }

    var color: Color {
        tone.color
    }

    var symbolName: String {
        switch self {
        case .added: "plus"
        case .removed: "minus"
        case .modified: "circle.lefthalf.filled"
        case .renamed: "arrow.right"
        case .copied: "doc.on.doc"
        case .unchanged: "circle"
        }
    }
}
