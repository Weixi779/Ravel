// Created by weixi on 2026/09/18.

import DesignSystem
import Localization
import SwiftUI

struct RevisionFileAttributes: View {
    let file: RevisionFilePresentation

    var body: some View {
        HStack(spacing: 5) {
            if file.hasConflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ChangeTone.conflict.color)
                    .help(I18n.diffConflict)
                    .accessibilityLabel(I18n.diffConflict)
            } else if file.resolvesConflict {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(ChangeTone.addition.color)
                    .help(I18n.diffResolvedConflict)
            }

            if file.executable || file.modeChanged {
                Image(systemName: file.executable ? "terminal" : "terminal.fill")
                    .foregroundStyle(.secondary)
                    .help(file.executable ? I18n.diffExecutable : I18n.diffExecutableRemoved)
            }

            if file.kind == .symlink {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                    .help(I18n.diffSymbolicLink)
            } else if file.kind == .submodule {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
                    .help(I18n.diffSubmodule)
            }

            if file.statistics?.isBinary == true {
                Image(systemName: "doc.zipper")
                    .foregroundStyle(.secondary)
                    .help(I18n.diffBinaryTitle)
            }
        }
        .font(.system(size: 10))
    }
}
