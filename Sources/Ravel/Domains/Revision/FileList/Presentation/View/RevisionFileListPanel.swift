//
//  RevisionFileListPanel.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import SwiftUI

struct RevisionFileListPanel: View {
    @Bindable var model: RevisionFileListViewModel
    let summary: RevisionChangeSummary
    @Binding var selection: String?
    @Binding var mode: RevisionFileListMode
    var splitSelection: RevisionSplitSelection?
    var moveFile: ((RevisionFilePresentation) -> Void)?
    var statisticsError: String?
    var retryStatistics: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            RevisionFileListHeader(
                summary: summary,
                searchText: $model.searchText,
                mode: $mode,
                statisticsError: statisticsError,
                retryStatistics: retryStatistics,
            )

            Divider()

            RevisionFileList(model: model, selection: $selection, mode: mode, splitSelection: splitSelection, moveFile: moveFile)
        }
    }
}

#if DEBUG
    #Preview("File list") {
        @Previewable @State var model = RevisionFileListPreviewData.makeModel()
        @Previewable @State var selection: String? = RevisionFileListPreviewData.files.first?.id
        @Previewable @State var mode = RevisionFileListMode.tree

        RevisionFileListPanel(
            model: model,
            summary: RevisionFileListPreviewData.summary,
            selection: $selection,
            mode: $mode,
        )
        .frame(width: 360, height: 440)
    }

    #Preview("Statistics retry") {
        @Previewable @State var model = RevisionFileListPreviewData.makeModel()
        @Previewable @State var selection: String?
        @Previewable @State var mode = RevisionFileListMode.grouped
        @Previewable @State var error: String? = "Unable to load change statistics."

        RevisionFileListPanel(
            model: model,
            summary: RevisionChangeSummary(files: RevisionFileListPreviewData.files, statistics: nil),
            selection: $selection,
            mode: $mode,
            statisticsError: error,
            retryStatistics: {
                error = nil
            },
        )
        .frame(width: 320, height: 440)
    }

    #Preview("Empty revision") {
        @Previewable @State var model = RevisionFileListPreviewData.makeModel(files: [])
        @Previewable @State var selection: String?
        @Previewable @State var mode = RevisionFileListMode.tree

        RevisionFileListPanel(
            model: model,
            summary: RevisionChangeSummary(files: [], statistics: nil),
            selection: $selection,
            mode: $mode,
        )
        .frame(width: 360, height: 300)
    }

    #Preview("No search matches") {
        @Previewable @State var model = RevisionFileListPreviewData.makeModel(searchText: "NoMatchingFile")
        @Previewable @State var selection: String?
        @Previewable @State var mode = RevisionFileListMode.list

        RevisionFileListPanel(
            model: model,
            summary: RevisionFileListPreviewData.summary,
            selection: $selection,
            mode: $mode,
        )
        .frame(width: 360, height: 300)
        .preferredColorScheme(.dark)
    }
#endif
