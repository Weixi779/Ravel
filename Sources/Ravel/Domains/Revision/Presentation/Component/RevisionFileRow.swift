// Created by weixi on 2026/09/17.

import DesignSystem
import Localization
import SwiftUI

struct RevisionFileRow: View {
    let file: RevisionFilePresentation
    var showsDirectory = false

    var body: some View {
        HStack(spacing: 7) {
            RevisionFileStatusIcon(status: file.status)

            FileTypeIcon(fileName: file.name)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: file.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if showsDirectory {
                    Text(verbatim: file.directory)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            RevisionFileAttributes(file: file)

            if let statistics = file.statistics, !statistics.isBinary {
                RevisionLineStatisticsView(additions: statistics.additions, deletions: statistics.deletions)
            }
        }
        .padding(.vertical, showsDirectory ? 4 : 2)
        .listRowSeparator(.hidden)
        .help(file.displayPath)
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button(I18n.diffCopyPath) {
                RevisionPathCopy.copy(file.path)
            }

            Button(I18n.diffCopyName) {
                RevisionPathCopy.copy(file.name)
            }
        }
    }
}

@MainActor
enum RevisionPathCopy {
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
