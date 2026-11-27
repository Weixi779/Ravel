//
//  RevisionOrganizationSheet.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Localization
import SwiftUI

struct RevisionOrganizationSheet: View {
    let input: RevisionOrganizationRequest
    let files: [RevisionFilePresentation]
    let selection: RevisionSplitSelection?
    let revisions: [Revision]
    let hasMatchingSnapshot: Bool
    let busy: Bool
    let loading: Bool
    let loadRemaining: () async -> Void
    let cancel: () -> Void
    let confirm: (Revision?, Set<String>?) -> Void
    @State private var pickedFiles: Set<String>?
    @State private var destination: Revision?

    private var picksDestination: Bool {
        switch input.action {
        case .squash, .moveFile: true
        default: false
        }
    }

    private var title: LocalizedStringResource {
        switch input.action {
        case .split: input.source.isWorkingCopy ? I18n.organizeSnapshot : I18n.splitReview
        case .confirmSplit: I18n.organizeSplit
        case .squash: I18n.organizeSquash
        case .moveFile: I18n.organizeMove
        case .resolveFile: I18n.organizeResolve
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if picksDestination {
                RevisionTargetPicker(
                    source: input.source,
                    revisions: revisions,
                    selection: $destination,
                    accepts: { !$0.isImmutable },
                    loadRemaining: loadRemaining,
                    isLoading: loading,
                )

                if revisions.contains(where: \.isImmutable) {
                    Text(I18n.organizeMutableDestination)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let destination {
                    Text(verbatim: "\(input.source.shortChangeID) → \(destination.shortChangeID)  \(destination.displaySummary)")
                        .textSelection(.enabled)
                }
            } else {
                Text(verbatim: "\(input.source.shortChangeID)  \(input.source.displaySummary)")
                    .textSelection(.enabled)
            }

            switch input.action {
            case let .moveFile(path), let .resolveFile(path):
                Text(verbatim: path)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            case .confirmSplit:
                if let selection {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(files.filter { $0.status != .unchanged }) { file in
                                LabeledContent {
                                    switch selection.first[file.path] {
                                    case .file: Text(I18n.splitFirst)
                                    case .hunks: Text(I18n.splitPartial)
                                    case nil: Text(I18n.splitSecond)
                                    }
                                } label: {
                                    Text(verbatim: file.displayPath)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)

                    if selection.leavesSecondEmpty {
                        LabeledContent {
                            Text(I18n.historyEmptyBadge)
                        } label: {
                            Text(I18n.splitSecond)
                        }
                    }
                }
            case .squash:
                let candidates = files.filter { $0.status != .unchanged }
                if !candidates.isEmpty {
                    DisclosureGroup(I18n.diffChangedFiles) {
                        ScrollView {
                            LazyVStack(alignment: .leading) {
                                ForEach(candidates) { file in
                                    Toggle(isOn: Binding(get: { pickedFiles?.contains(file.path) ?? true }, set: { included in
                                        let all = Set(candidates.map(\.path))
                                        var picked = pickedFiles ?? all
                                        if included { picked.insert(file.path) } else { picked.remove(file.path) }
                                        pickedFiles = picked == all ? nil : picked
                                    })) {
                                        Text(verbatim: file.displayPath)
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                        .frame(maxHeight: 120)
                    }
                }
            case .split: EmptyView()
            }

            if input.source.isImmutable {
                Text(I18n.historyImmutableReason(input.source.shortChangeID))
            } else if picksDestination, !hasMatchingSnapshot {
                Text(I18n.organizeStale)
            }

            HStack {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button(I18n.historyCancel) {
                    cancel()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(busy)

                Button(title) {
                    confirm(destination, pickedFiles)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(busy || pickedFiles?.isEmpty == true || input.source.isImmutable || (picksDestination && (destination == nil || !hasMatchingSnapshot)))
            }
        }
        .padding(20)
        .frame(width: 510)
        .interactiveDismissDisabled(busy)
        .onAppear {
            if picksDestination, input.source.parentIDs.count == 1 {
                destination = revisions.first { $0.id == input.source.parentIDs.first && !$0.isImmutable }
            }
        }
    }
}

#if DEBUG
    #Preview("Review split") {
        let selection = RevisionSplitPreviewData.selection()
        RevisionOrganizationSheet(
            input: .init(action: .confirmSplit, source: selection.source, request: selection.request),
            files: [RevisionFilePresentation(RevisionSplitPreviewData.file)],
            selection: selection,
            revisions: [],
            hasMatchingSnapshot: true,
            busy: false,
            loading: false,
            loadRemaining: {},
            cancel: {},
            confirm: { _, _ in },
        )
    }
#endif
