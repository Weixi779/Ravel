//
//  RevisionDescriptionEditor.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Localization
import SwiftUI

struct RevisionDescriptionEditor: View {
    let revision: Revision
    @State private var draft: RevisionDescriptionDraft
    let cancel: () -> Void
    let save: (RevisionDescriptionDraft) -> Void

    init(revision: Revision, cancel: @escaping () -> Void, save: @escaping (RevisionDescriptionDraft) -> Void) {
        self.revision = revision
        _draft = State(initialValue: RevisionDescriptionDraft(revision.description))
        self.cancel = cancel
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(I18n.historyDescribe)
                .font(.headline)

            Text(verbatim: revision.changeID)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)

            TextField(text: $draft.title) {
                Text(I18n.historyDescriptionTitle)
            }

            Text(I18n.historyDescriptionBody)
                .font(.subheadline)

            TextEditor(text: $draft.body)
                .accessibilityLabel(I18n.historyDescriptionBody)
                .frame(minHeight: 130)
                .border(.quaternary)

            HStack {
                Spacer()

                Button(I18n.historyCancel) {
                    cancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(I18n.historySave) {
                    save(draft)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

#if DEBUG
    #Preview {
        RevisionDescriptionEditor(revision: HistoryPreviewData.source, cancel: {}, save: { _ in })
    }
#endif
