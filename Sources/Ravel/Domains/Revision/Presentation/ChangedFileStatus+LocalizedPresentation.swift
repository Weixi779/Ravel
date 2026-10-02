//
//  ChangedFileStatus+LocalizedPresentation.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
import Localization

nonisolated extension RevisionFilePresentation.Status {
    var localizedName: LocalizedStringResource {
        switch self {
        case .modified: I18n.diffModified
        case .added: I18n.diffAdded
        case .removed: I18n.diffRemoved
        case .copied: I18n.diffCopied
        case .renamed: I18n.diffRenamed
        case .unchanged: I18n.diffUnchanged
        }
    }
}
