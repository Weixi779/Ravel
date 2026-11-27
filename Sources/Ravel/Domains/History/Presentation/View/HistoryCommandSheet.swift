//
//  HistoryCommandSheet.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Localization
import SwiftUI

struct HistoryCommandSheet: View {
    let request: HistoryCommandRequest
    let log: RepositoryLog
    let isLoading: Bool
    let loadRemaining: () async -> Void
    let cancel: () -> Void
    let locate: (String) -> Void
    let submit: (HistoryRevision, RevisionGraphCommand) -> Void
    var pageError: String?
    var retry: () -> Void = {}
    @State private var destination: Revision?
    @State private var name = ""
    @State private var includeDescendants = false

    private var current: Bool {
        guard let source = request.source else { return true }
        return source.repositoryURL == log.repositoryURL && source.operationID == log.operationID
    }

    private var descendants: Set<String> {
        request.source.map { log.descendantIDs(of: $0.revision) } ?? []
    }

    private var valid: Bool {
        guard current else { return false }
        switch request {
        case .find, .moveBookmark: return destination != nil
        case .rebase: return destination.map { !includeDescendants || !descendants.contains($0.id) } == true
        case .createBookmark: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .deleteBookmark: return true
        }
    }

    var body: some View {
        let excluded = includeDescendants ? descendants : []
        VStack(alignment: .leading, spacing: 12) {
            Text(request.title)
                .font(.headline)

            if case .rebase = request {
                Picker(selection: $includeDescendants) {
                    Text(I18n.historyOnlyThis)
                        .tag(false)

                    Text(I18n.historyWithDescendants)
                        .tag(true)
                } label: {
                    Text(I18n.historyScope)
                }
                .pickerStyle(.segmented)
            }

            if request.needsPicker {
                RevisionTargetPicker(
                    source: request.source?.revision,
                    revisions: log.revisions,
                    selection: $destination,
                    accepts: { revision in !excluded.contains(revision.id) },
                    loadRemaining: loadRemaining,
                    isLoading: isLoading,
                )

                if let pageError {
                    Text(verbatim: pageError)

                    Button(I18n.commonRetry) {
                        retry()
                    }
                }
            } else if let source = request.source {
                Text(verbatim: "\(source.revision.shortChangeID)  \(source.revision.displaySummary)")
                    .textSelection(.enabled)
            }

            if case .createBookmark = request {
                TextField(text: $name) {
                    Text(I18n.historyBookmarkName)
                }
            }

            if !current {
                Text(I18n.historyReviewNewSnapshot)
                    .foregroundStyle(.secondary)
            } else if let summary {
                Text(summary)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()

                Button(I18n.historyCancel) {
                    cancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(request.title) {
                    confirm()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(20)
        .frame(width: 540)
        .frame(minHeight: request.needsPicker ? 310 : nil)
    }

    private var summary: LocalizedStringResource? {
        guard let source = request.source?.revision else { return nil }
        switch request {
        case .rebase:
            guard let destination else { return nil }
            return includeDescendants ? I18n.historyRebaseStackSummary(source.shortChangeID, descendants.count, destination.shortChangeID)
                : I18n.historyRebaseOneSummary(source.shortChangeID, destination.shortChangeID)
        case let .moveBookmark(_, name):
            return destination.map { I18n.historyMoveBookmarkSummary(name, bookmarkOrigin(name, source: source), $0.shortChangeID) }
        case let .deleteBookmark(_, name): return I18n.historyDeleteBookmarkSummary(name, bookmarkOrigin(name, source: source))
        default: return nil
        }
    }

    private func bookmarkOrigin(_ name: String, source: Revision) -> String {
        guard let bookmark = log.localBookmarks.first(where: { $0.name == name }), bookmark.commitIDs.count > 1 else { return source.shortChangeID }
        return bookmark.commitIDs.map { String($0.prefix(12)) }.joined(separator: ", ")
    }

    private func confirm() {
        guard valid else { return }
        switch request {
        case .find:
            if let destination { locate(destination.id) }
        case let .rebase(source):
            if let destination { submit(source, .rebase(destination: log.target(for: destination).writeTarget, descendants: includeDescendants)) }
        case let .createBookmark(source):
            submit(source, .createBookmark(name: name))
        case let .moveBookmark(source, name):
            if let destination { submit(source, .moveBookmark(name: name, destination: log.target(for: destination).writeTarget)) }
        case let .deleteBookmark(source, name):
            submit(source, .deleteBookmark(name: name))
        }
    }
}

#if DEBUG
    #Preview {
        let revision = HistoryPreviewData.source
        if let graph = try? LogGraph(revisions: [revision]) {
            let log = RepositoryLog(repositoryURL: URL(filePath: "/preview"), operationID: "preview", revisions: [revision], graph: graph, hasMore: false, backendVersion: "Preview")
            HistoryCommandSheet(request: .createBookmark(log.target(for: revision)), log: log, isLoading: false, loadRemaining: {}, cancel: {}, locate: { _ in }, submit: { _, _ in })
        }
    }
#endif
