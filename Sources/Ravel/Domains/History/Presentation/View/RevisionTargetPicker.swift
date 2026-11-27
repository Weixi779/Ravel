//
//  RevisionTargetPicker.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Localization
import SwiftUI

struct RevisionTargetPicker: View {
    let source: Revision?
    let revisions: [Revision]
    @Binding var selection: Revision?
    var accepts: (Revision) -> Bool = { _ in true }
    var loadRemaining: () async -> Void = {}
    var isLoading = false
    @State private var query = ""

    static func matches(_ revision: Revision, query: String) -> Bool {
        query.isEmpty || revision.changeID.localizedCaseInsensitiveContains(query)
            || revision.description.localizedStandardContains(query)
            || revision.bookmarks.contains { $0.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let source {
                LabeledContent {
                    Text(verbatim: "\(source.shortChangeID)  \(source.displaySummary)")
                        .lineLimit(2)
                        .textSelection(.enabled)
                } label: {
                    Text(I18n.historySource)
                }
            }

            TextField(text: $query) {
                Text(I18n.historySearchHint)
            }

            List(selection: $selection) {
                ForEach(revisions.filter { Self.matches($0, query: query) }) { revision in
                    HStack {
                        Text(verbatim: revision.shortChangeID)
                            .font(.system(.caption, design: .monospaced))

                        Text(verbatim: revision.displaySummary)
                            .lineLimit(1)

                        Spacer()

                        Text(verbatim: revision.bookmarks.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(revision)
                    .selectionDisabled(revision.id == source?.id || !accepts(revision))
                }
            }
            .frame(minHeight: 160)

            if isLoading {
                ProgressView(I18n.historyLoadingMore)
                    .controlSize(.small)
            }
        }
        .task { await loadRemaining() }
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var selected: Revision?
        RevisionTargetPicker(source: nil, revisions: [HistoryPreviewData.source], selection: $selected)
            .padding()
            .frame(width: 480, height: 310)
    }
#endif
