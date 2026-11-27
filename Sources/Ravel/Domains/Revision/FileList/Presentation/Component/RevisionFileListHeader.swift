//
//  RevisionFileListHeader.swift
//  Ravel
//
//  Created by weixi on 2026/10/02.
//  Copyright © 2026 Ravel. All rights reserved.
//

import DesignSystem
import Localization
import SwiftUI

struct RevisionFileListHeader: View {
    let summary: RevisionChangeSummary
    @Binding var searchText: String
    @Binding var mode: RevisionFileListMode
    let statisticsError: String?
    let retryStatistics: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                Text(I18n.diffChangedFiles)
                    .fontWeight(.medium)

                Text(summary.fileCount, format: .number)
                    .foregroundStyle(.secondary)

                RevisionLineStatisticsView(additions: summary.additions, deletions: summary.deletions)

                Spacer(minLength: 0)

                if let statisticsError {
                    Button(action: retryStatistics) {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(statisticsError)
                    .accessibilityLabel(I18n.diffStatisticsRetry)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    changeCounts

                    Spacer(minLength: 0)

                    layoutPicker
                }

                VStack(alignment: .leading, spacing: 7) {
                    changeCounts

                    HStack {
                        Spacer(minLength: 0)

                        layoutPicker
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(text: $searchText, prompt: Text(I18n.diffSearchFiles)) {
                    Text(I18n.diffSearchFiles)
                }
                .textFieldStyle(.plain)
                .accessibilityIdentifier("diff.fileSearch")

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(I18n.diffClearSearch)
                }
            }
            .padding(6)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
        }
        .font(.system(size: 11))
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var changeCounts: some View {
        HStack(spacing: 7) {
            ForEach(RevisionFilePresentation.Status.allCases.filter { $0 != .unchanged }, id: \.self) { status in
                if let count = summary.statusCounts[status], count > 0 {
                    HStack(spacing: 3) {
                        RevisionFileStatusBadge(status: status)

                        Text(count, format: .number)
                            .foregroundStyle(.secondary)
                    }
                    .help(status.localizedName)
                }
            }

            if summary.conflicts > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ChangeTone.conflict.color)
                    .help(I18n.diffConflict)

                Text(summary.conflicts, format: .number)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
    }

    private var layoutPicker: some View {
        Picker(I18n.diffFileList, selection: $mode) {
            Image(systemName: "list.bullet.indent")
                .help(I18n.diffFileTree)
                .tag(RevisionFileListMode.tree)

            Image(systemName: "folder")
                .help(I18n.diffFileGroups)
                .tag(RevisionFileListMode.grouped)

            Image(systemName: "list.bullet")
                .help(I18n.diffFileList)
                .tag(RevisionFileListMode.list)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 94)
        .accessibilityIdentifier("diff.fileGrouping")
    }
}

#if DEBUG
    #Preview("Header controls") {
        @Previewable @State var searchText = ""
        @Previewable @State var mode = RevisionFileListMode.tree
        @Previewable @State var statisticsError: String? = "Statistics are temporarily unavailable."

        RevisionFileListHeader(
            summary: RevisionFileListPreviewData.summary,
            searchText: $searchText,
            mode: $mode,
            statisticsError: statisticsError,
            retryStatistics: { statisticsError = nil },
        )
        .frame(width: 300)
    }
#endif
