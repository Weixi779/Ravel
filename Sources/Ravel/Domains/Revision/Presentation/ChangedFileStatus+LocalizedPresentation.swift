// Created by weixi on 2026/09/17.

import Foundation
import Localization

nonisolated extension ChangedFile.Status {
    var localizedName: LocalizedStringResource {
        switch self {
        case .modified: I18n.diffModified
        case .added: I18n.diffAdded
        case .removed: I18n.diffRemoved
        case .copied: I18n.diffCopied
        case .renamed: I18n.diffRenamed
        }
    }
}
