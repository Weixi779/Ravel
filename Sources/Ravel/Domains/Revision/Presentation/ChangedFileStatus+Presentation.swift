//
//  ChangedFileStatus+Presentation.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
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
}
