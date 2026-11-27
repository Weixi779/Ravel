//
//  RevisionInspectorView.swift
//  Ravel
//
//  Created by weixi on 2026/09/09.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Localization
import SwiftUI

struct RevisionInspectorView: View {
    let revision: Revision?
    let request: RevisionDiffRequest?
    @Bindable var diff: RevisionChangesSession
    @Environment(DiffViewOptions.self) private var options
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        @Bindable var options = options

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Picker(I18n.revisionInformation, selection: $diff.showsDetails) {
                    Text(I18n.revisionChangesTab)
                        .tag(false)

                    Text(I18n.revisionDetailsTab)
                        .tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                HStack(spacing: 12) {
                    if revision != nil {
                        Text(verbatim: diff.showsDetails ? revision?.shortChangeID ?? "" : diff.displayedChangeID)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Text(verbatim: diff.showsDetails ? revision?.displaySummary ?? "" : diff.displayedTitle)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if diff.isSelectingSplit {
                        Button(I18n.splitCancel) {
                            diff.endSplit()
                        }
                    } else if let revision, let request {
                        Button(I18n.splitReview) {
                            diff.beginSplit(revision, request: request)
                        }
                        .disabled(revision.isImmutable || diff.isLoading || diff.files.isEmpty)
                    }

                    if diff.showsRevisionProgress {
                        ProgressView()
                            .controlSize(.small)
                            .help(I18n.diffLoadingChanges)
                    }

                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, height: 28)
                        .overlay {
                            RevisionInspectorResizeHandle()
                        }
                        .accessibilityHidden(true)
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(.bar)

            Divider()

            if diff.showsDetails {
                RevisionDetailView(revision: revision)
            } else if revision == nil {
                placeholder(I18n.revisionSelect, symbol: "cursorarrow.click")
            } else if let error = diff.errorMessage {
                placeholder(I18n.diffLoadFailed, symbol: "exclamationmark.triangle", detail: Text(verbatim: error))
            } else if !diff.files.isEmpty {
                HSplitView {
                    RevisionFileListPanel(model: diff.fileList, summary: diff.summary, selection: Binding(
                        get: { diff.selectedFileID },
                        set: { id in
                            guard let id else { return }
                            diff.selectFile(id)
                        },
                    ), mode: $options.fileListMode, splitSelection: diff.splitSelection, statisticsError: diff.statisticsErrorMessage, retryStatistics: diff.retryStatistics)
                        .frame(minWidth: 290, idealWidth: 340, maxWidth: 520)
                        .allowsHitTesting(!diff.isLoading)

                    fileContent
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.quaternary, lineWidth: 1)
                        }
                        .padding(10)
                }
            } else if !diff.isLoading {
                placeholder(I18n.diffEmptyTitle, symbol: "checkmark.circle", detail: Text(I18n.diffEmptyDetail))
            } else {
                Color.clear
            }
        }
        .onChange(of: request, initial: true) { _, request in
            diff.selectRevision(request, revision: revision)
        }
        .onDisappear {
            diff.selectRevision(nil)
        }
    }

    private var fileContent: some View {
        VStack(spacing: 0) {
            if let file = diff.displayedFile {
                RevisionFileHeader(
                    file: file,
                    repositoryURL: request?.repositoryURL,
                    isLoading: diff.showsFileProgress,
                    canSearch: diff.fileDiff?.isBinary == false,
                    options: options,
                    showsInformation: $diff.showsFileInformation,
                )
                    {
                        diff.findRequest += 1
                }

                Divider()
            }

            if let selection = diff.splitSelection, let file = diff.displayedFile, diff.selectedFileID == file.id {
                RevisionSplitReview(selection: selection, file: file, content: diff.fileDiff)

                Divider()
            }

            if let error = diff.fileErrorMessage {
                placeholder(I18n.diffDisplayFailed, symbol: "exclamationmark.triangle", detail: Text(verbatim: error))
            } else if let content = diff.fileDiff {
                if content.isBinary {
                    placeholder(I18n.diffBinaryTitle, symbol: "doc.zipper", detail: Text(I18n.diffBinaryDetail))
                } else if content.unified.rows.isEmpty {
                    if diff.displayedFile?.hasConflict == true {
                        placeholder(I18n.diffConflict, symbol: "exclamationmark.triangle", detail: Text(I18n.diffInheritedConflict))
                    } else {
                        placeholder(I18n.diffNoTextTitle, symbol: "doc", detail: Text(I18n.diffNoTextDetail))
                    }
                } else {
                    RevisionDiffView(
                        diff: content,
                        sideBySide: options.sideBySide,
                        showsChangeMarkers: options.showsChangeMarkers ?? differentiateWithoutColor,
                        findRequest: diff.findRequest,
                    )
                }
            } else {
                placeholder(I18n.diffSelectFile, symbol: "doc.text.magnifyingglass")
            }
        }
    }

    private func placeholder(_ title: LocalizedStringResource, symbol: String, detail: Text? = nil) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 13, weight: .medium))

            if let detail {
                detail
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
