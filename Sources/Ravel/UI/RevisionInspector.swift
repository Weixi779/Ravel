// Created by weixi on 2026/09/09.

import SwiftUI

struct RevisionInspector: View {
    let revision: Revision?
    let request: DiffSession.Request?
    @State private var diff = DiffSession()
    @State private var showsDetails = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Revision information", selection: $showsDetails) {
                    Text("Changes").tag(false)
                    Text("Details").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                if let revision {
                    Text(revision.shortChangeID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(revision.summary)
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
                placeholder("Select a change", symbol: "cursorarrow.click")
            } else if diff.isLoading {
                ProgressView("Loading changes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = diff.errorMessage {
                placeholder("Couldn't load changes", symbol: "exclamationmark.triangle", detail: error)
            } else if let changes = diff.diff {
                VStack(spacing: 0) {
                    if let warning = changes.warning { warningBar(warning) }
                    if changes.files.isEmpty {
                        placeholder("No file changes", symbol: "checkmark.circle", detail: "This revision has the same contents as its merged parents.")
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
                Text("Changed Files").fontWeight(.medium)
                Spacer()
                Text("\(files.count)").foregroundStyle(.secondary)
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
                    .help("\(file.status.rawValue.capitalized): \(file.displayPath)")
                    .contextMenu {
                        Button("Copy File Path") {
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
                    Text(file.status.rawValue.capitalized).foregroundStyle(statusColor(file.status))
                }
                .font(.system(size: 11))
                .padding(.horizontal, 12)
                .frame(height: 30)
                Divider()
            }
            if diff.isLoadingFile {
                ProgressView("Loading diff…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = diff.fileErrorMessage {
                placeholder("Couldn't display this diff", symbol: "exclamationmark.triangle", detail: error)
            } else if let content = diff.fileDiff {
                if let warning = content.warning { warningBar(warning) }
                if content.isBinary {
                    placeholder("Binary file changed", symbol: "doc.zipper", detail: "A text diff isn't available for this file.")
                } else if content.lines.isEmpty {
                    placeholder("No text diff", symbol: "doc", detail: "No patch was returned for this file. Refresh the log to reload its changes.")
                } else {
                    DiffTextView(diff: content)
                }
            } else {
                placeholder("Select a file", symbol: "doc.text.magnifyingglass")
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
