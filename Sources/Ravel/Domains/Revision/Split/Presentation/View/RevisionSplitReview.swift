//
//  RevisionSplitReview.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Localization
import SwiftUI

struct RevisionSplitReview: View {
    let selection: RevisionSplitSelection
    let file: RevisionFilePresentation
    let content: RevisionDiffPresentation?

    var body: some View {
        let hunks = file.allowsHunkSelection ? content?.hunks ?? [] : []
        VStack(alignment: .leading, spacing: 5) {
            if hunks.isEmpty {
                Text(I18n.splitFileOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(hunks, id: \.range) { hunk in
                            let included = selection.includes(hunk.range, in: file.path)
                            Toggle(isOn: Binding(get: { included }, set: { value in
                                selection.setHunk(hunk.range, included: value, in: file.path, available: hunks.map(\.range))
                            })) {
                                HStack {
                                    Text(verbatim: hunk.label)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    Spacer()

                                    Text(included ? I18n.splitFirst : I18n.splitSecond)
                                        .font(.caption)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(height: min(CGFloat(hunks.count) * 24, 110))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

#if DEBUG
    #Preview("Two independent hunks") {
        @Previewable @State var selection = RevisionSplitPreviewData.selection()
        @Previewable @State var sideBySide = false
        let content = RevisionSplitPreviewData.presentation

        VStack {
            Toggle(I18n.diffSideBySide, isOn: $sideBySide)

            RevisionSplitReview(selection: selection, file: RevisionFilePresentation(RevisionSplitPreviewData.file), content: content)

            RevisionDiffView(diff: content, sideBySide: sideBySide)
        }
        .padding()
        .frame(width: 720, height: 420)
    }
#endif
