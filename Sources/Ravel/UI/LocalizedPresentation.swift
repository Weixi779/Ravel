// Created by weixi on 2026/09/12.

import Foundation
import Localization

nonisolated extension Revision {
    var displaySummary: String {
        summary.isEmpty ? String(localized: I18n.commonNoDescription) : summary
    }
}

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

nonisolated extension JJClient.Failure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            String(localized: I18n.errorsExecutableNotFound)
        case .invalidExecutable(let path):
            String(localized: I18n.errorsInvalidExecutable(path))
        case .invalidDirectory(let path):
            String(localized: I18n.errorsInvalidDirectory(path))
        case .unsupportedVersion(let version):
            String(localized: I18n.errorsUnsupportedVersion(version))
        case .commandFailed(let message):
            message
        case .commandExited(let status):
            String(localized: I18n.errorsCommandExited(status))
        case .malformedOutput(let line):
            String(localized: I18n.errorsMalformedOutput(line))
        case .duplicateCommit:
            String(localized: I18n.errorsDuplicateCommit)
        }
    }
}

nonisolated extension FileDiff.Failure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .malformedPatch: String(localized: I18n.errorsMalformedPatch)
        case .tooLarge: String(localized: I18n.errorsDiffTooLarge)
        }
    }
}
