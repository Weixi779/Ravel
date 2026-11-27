//
//  RevisionFileRow.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import DesignSystem
import Localization
import SwiftUI

struct RevisionFileRow: View {
    let file: RevisionFilePresentation
    var showsDirectory = false
    var moveFile: ((RevisionFilePresentation) -> Void)?

    var body: some View {
        HStack(spacing: 7) {
            RevisionFileStatusBadge(status: file.status)

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
            if let moveFile, file.status != .unchanged {
                Button(I18n.organizeMove) {
                    moveFile(file)
                }

                Divider()
            }

            Button(I18n.diffCopyPath) {
                RevisionPathCopy.copy(file.path)
            }

            Button(I18n.diffCopyName) {
                RevisionPathCopy.copy(file.name)
            }
        }
    }
}

#if DEBUG
    #Preview("File statuses") {
        VStack(spacing: 12) {
            ForEach(RevisionFileListPreviewData.files) { file in
                RevisionFileRow(file: file, showsDirectory: true)
            }
        }
        .padding()
        .frame(width: 420)
    }
#endif
