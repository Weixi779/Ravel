// Created by weixi on 2026/09/09.

import SwiftUI
import Localization

struct RevisionInspector: View {
    let revision: Revision?
    let request: DiffSession.Request?
    @State private var diff = DiffSession()
    @State private var showsDetails = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker(String(localized: I18n.revisionInformation), selection: $showsDetails) {
                    Text(I18n.revisionChangesTab).tag(false)
                    Text(I18n.revisionDetailsTab).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                if let revision {
                    Text(revision.shortChangeID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(revision.displaySummary)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .help(revision.description)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.bar)
            Divider()
            if showsDetails {
                RevisionDetail(revision: revision)
            } else if revision == nil {
                placeholder(String(localized: I18n.revisionSelect), symbol: "cursorarrow.click")
            } else if diff.isLoading {
                ProgressView(String(localized: I18n.diffLoadingChanges))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = diff.errorMessage {
                placeholder(String(localized: I18n.diffLoadFailed), symbol: "exclamationmark.triangle", detail: error)
            } else if let changes = diff.diff {
                VStack(spacing: 0) {
                    if let warning = changes.warning { warningBar(warning) }
                    if changes.files.isEmpty {
                        placeholder(String(localized: I18n.diffEmptyTitle), symbol: "checkmark.circle", detail: String(localized: I18n.diffEmptyDetail))
                    } else {
                        HSplitView {
                            fileList(changes.files)
                                .frame(minWidth: 175, idealWidth: 245, maxWidth: 320)
                            fileContent
                                .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            } else {
                Color.clear
            }
        }
        .onChange(of: request, initial: true) { _, request in diff.selectRevision(request) }
        .onDisappear { diff.selectRevision(nil) }
    }

    private func fileList(_ files: [ChangedFile]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(I18n.diffChangedFiles).fontWeight(.medium)
                Spacer()
                Text(files.count, format: .number).foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 12)
            .frame(height: 30)
            Divider()
            List(selection: Binding(get: { diff.selectedFileID }, set: { diff.selectFile($0) })) {
                ForEach(files) { file in
                    HStack(alignment: .top, spacing: 8) {
                        Text(file.status.letter)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(statusColor(file.status))
                            .frame(width: 14)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(URL(fileURLWithPath: file.path).lastPathComponent)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if file.sourcePath != file.path || file.path.contains("/") {
                                Text(file.displayPath)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(file.id)
                    .help(String(localized: I18n.diffFileHelp(String(localized: file.status.localizedName), file.displayPath)))
                    .contextMenu {
                        Button(String(localized: I18n.diffCopyPath)) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(file.path, forType: .string)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var fileContent: some View {
        VStack(spacing: 0) {
            if let file = diff.selectedFile {
                HStack(spacing: 8) {
                    Text(file.displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(file.displayPath)
                    Spacer(minLength: 0)
                    Text(file.status.localizedName).foregroundStyle(statusColor(file.status))
                }
                .font(.system(size: 11))
                .padding(.horizontal, 12)
                .frame(height: 30)
                Divider()
            }
            if diff.isLoadingFile {
                ProgressView(String(localized: I18n.diffLoading))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = diff.fileErrorMessage {
                placeholder(String(localized: I18n.diffDisplayFailed), symbol: "exclamationmark.triangle", detail: error)
            } else if let content = diff.fileDiff {
                if let warning = content.warning { warningBar(warning) }
                if content.isBinary {
                    placeholder(String(localized: I18n.diffBinaryTitle), symbol: "doc.zipper", detail: String(localized: I18n.diffBinaryDetail))
                } else if content.lines.isEmpty {
                    placeholder(String(localized: I18n.diffNoTextTitle), symbol: "doc", detail: String(localized: I18n.diffNoTextDetail))
                } else {
                    DiffTextView(diff: content)
                }
            } else {
                placeholder(String(localized: I18n.diffSelectFile), symbol: "doc.text.magnifyingglass")
            }
        }
    }

    private func placeholder(_ title: String, symbol: String, detail: String? = nil) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 13, weight: .medium))
            if let detail {
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func warningBar(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusColor(_ status: ChangedFile.Status) -> Color {
        switch status {
        case .added: .green
        case .removed: .red
        case .modified: .orange
        case .copied, .renamed: .teal
        }
    }
}
