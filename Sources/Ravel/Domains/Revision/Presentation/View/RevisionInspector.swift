// Created by weixi on 2026/09/09.

import Localization
import SwiftUI

struct RevisionInspector: View {
    let revision: Revision?
    let request: RevisionDiffRequest?
    @Bindable var diff: DiffSession
    @State private var showsDetails = false
    @Environment(DiffViewOptions.self) private var options
    @State private var findRequest = 0
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

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
                    if changes.files.isEmpty {
                        placeholder(String(localized: I18n.diffEmptyTitle), symbol: "checkmark.circle", detail: String(localized: I18n.diffEmptyDetail))
                    } else {
                        HSplitView {
                            fileList(changes.files)
                                .frame(minWidth: 190, idealWidth: 280, maxWidth: 480)
                            fileContent
                                .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(nsColor: .textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1)
                                }
                                .padding(10)
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
        ChangedFilesView(files: files, selection: Binding(
            get: { diff.selectedFileID },
            set: { id in
                guard let id, id != diff.selectedFileID, files.contains(where: { $0.id == id }) else { return }
                diff.selectFile(id)
            },
        ), options: options)
    }

    private var fileContent: some View {
        VStack(spacing: 0) {
            if let file = diff.selectedFile {
                HStack(spacing: 8) {
                    ChangedFileStatusIcon(status: file.status)
                    Text(file.displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(file.displayPath)
                    Spacer(minLength: 0)
                    if diff.fileDiff?.isBinary == false {
                        Button { findRequest += 1 } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: I18n.diffFind))
                        .accessibilityLabel(String(localized: I18n.diffFind))
                        Button {
                            guard let content = diff.fileDiff else { return }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(content.lines.map(\.text).joined(separator: "\n") + "\n", forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: I18n.diffCopy))
                        .accessibilityLabel(String(localized: I18n.diffCopy))
                    }
                }
                .font(.system(size: 11))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(file.status.color.opacity(0.06))
                Divider()
            }
            if diff.isLoadingFile {
                ProgressView(String(localized: I18n.diffLoading))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = diff.fileErrorMessage {
                placeholder(String(localized: I18n.diffDisplayFailed), symbol: "exclamationmark.triangle", detail: error)
            } else if let content = diff.fileDiff {
                if content.isBinary {
                    placeholder(String(localized: I18n.diffBinaryTitle), symbol: "doc.zipper", detail: String(localized: I18n.diffBinaryDetail))
                } else if content.lines.isEmpty {
                    placeholder(String(localized: I18n.diffNoTextTitle), symbol: "doc", detail: String(localized: I18n.diffNoTextDetail))
                } else {
                    DiffTextView(diff: content, showsChangeMarkers: options.showsChangeMarkers ?? differentiateWithoutColor, findRequest: findRequest)
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
}
