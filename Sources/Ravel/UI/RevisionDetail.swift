// Created by weixi on 2026/09/09.

import SwiftUI

struct RevisionDetail: View {
    let revision: Revision?

    var body: some View {
        if let revision {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Text("Commit Details").font(.headline)
                        if revision.isWorkingCopy { badge("Working copy", color: .teal) }
                        if revision.isImmutable { badge("Immutable", color: .secondary) }
                        if revision.hasConflict { badge("Conflict", color: .orange) }
                        if revision.isDivergent { badge("Divergent", color: .purple) }
                        Spacer()
                    }
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 8) {
                            metadata("Change", value: revision.changeID, monospaced: true)
                            metadata("Commit", value: revision.commitID, monospaced: true)
                            metadata("Author", value: "\(revision.author) <\(revision.email)>")
                            metadata("Date", value: revision.timestamp.formatted(date: .abbreviated, time: .standard))
                            if !revision.bookmarks.isEmpty {
                                metadata("Bookmarks", value: revision.bookmarks.joined(separator: ", "))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(revision.description.isEmpty ? "No description" : revision.description)
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
            ContentUnavailableView("Select a change", systemImage: "cursorarrow.click", description: Text("Its description and details will appear here."))
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
