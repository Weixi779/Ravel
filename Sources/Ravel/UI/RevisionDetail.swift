// Created by weixi on 2026/09/09.

import Localization
import SwiftUI

struct RevisionDetail: View {
    let revision: Revision?

    var body: some View {
        if let revision {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Text(I18n.revisionDetails).font(.headline)
                        if revision.isWorkingCopy { badge(String(localized: I18n.revisionWorkingCopy), color: .teal) }
                        if revision.isImmutable { badge(String(localized: I18n.revisionImmutable), color: .secondary) }
                        if revision.hasConflict { badge(String(localized: I18n.revisionConflict), color: .orange) }
                        if revision.isDivergent { badge(String(localized: I18n.revisionDivergent), color: .purple) }
                        Spacer()
                    }
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 8) {
                            metadata(String(localized: I18n.revisionChange), value: revision.changeID, monospaced: true)
                            metadata(String(localized: I18n.revisionCommit), value: revision.commitID, monospaced: true)
                            metadata(String(localized: I18n.revisionAuthor), value: "\(revision.author) <\(revision.email)>")
                            metadata(String(localized: I18n.revisionDate), value: revision.timestamp.formatted(date: .abbreviated, time: .standard))
                            if !revision.bookmarks.isEmpty {
                                metadata(String(localized: I18n.revisionBookmarks), value: revision.bookmarks.joined(separator: ", "))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(revision.description.isEmpty ? String(localized: I18n.commonNoDescription) : revision.description)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .textSelection(.enabled)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            ContentUnavailableView(String(localized: I18n.revisionSelect), systemImage: "cursorarrow.click", description: Text(I18n.revisionSelectDetail))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func metadata(_ title: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(size: 11, design: .monospaced) : .system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
        .font(.system(size: 12))
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: Capsule())
    }
}
