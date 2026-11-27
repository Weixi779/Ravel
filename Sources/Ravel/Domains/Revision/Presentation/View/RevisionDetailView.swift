//
//  RevisionDetailView.swift
//  Ravel
//
//  Created by weixi on 2026/09/09.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Localization
import SwiftUI

struct RevisionDetailView: View {
    let revision: Revision?

    var body: some View {
        if let revision {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Text(I18n.revisionDetails).font(.headline)
                        if revision.isWorkingCopy { badge(I18n.revisionWorkingCopy, color: .teal) }
                        if revision.isImmutable { badge(I18n.revisionImmutable, color: .secondary) }
                        if revision.hasConflict { badge(I18n.revisionConflict, color: .orange) }
                        if revision.isDivergent { badge(I18n.revisionDivergent, color: .purple) }
                        Spacer()
                    }
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 8) {
                            metadata(I18n.revisionChange, value: revision.changeID, monospaced: true)
                            metadata(I18n.revisionCommit, value: revision.commitID, monospaced: true)
                            metadata(I18n.revisionAuthor, value: "\(revision.author) <\(revision.email)>")
                            metadata(I18n.revisionDate, value: revision.timestamp.formatted(date: .abbreviated, time: .standard))
                            if !revision.bookmarks.isEmpty {
                                metadata(I18n.revisionBookmarks, value: revision.bookmarks.joined(separator: ", "))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        (revision.description.isEmpty ? Text(I18n.commonNoDescription) : Text(verbatim: revision.description))
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
            ContentUnavailableView(I18n.revisionSelect, systemImage: "cursorarrow.click", description: Text(I18n.revisionSelectDetail))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func metadata(_ title: LocalizedStringResource, value: String, monospaced: Bool = false) -> some View {
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

    private func badge(_ text: LocalizedStringResource, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: Capsule())
    }
}
