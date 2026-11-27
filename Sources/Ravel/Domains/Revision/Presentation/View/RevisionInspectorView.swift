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
    var logSession: LogSession?
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

                    if let split = diff.splitSelection {
                        Button(I18n.organizeSplit) {
                            diff.requestOrganization(.confirmSplit, source: split.source, request: split.request)
                        }
                        .disabled(!split.canSplit || diff.isOrganizing)

                        Button(I18n.splitCancel) {
                            diff.endSplit()
                        }
                    } else if let revision, let request {
                        Button(I18n.splitReview) {
                            diff.requestOrganization(.split, source: revision, request: request)
                        }
                        .disabled(revision.isImmutable || diff.isLoading || (!revision.isWorkingCopy && diff.files.isEmpty))
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
                    ), mode: $options.fileListMode, splitSelection: diff.splitSelection, moveFile: { file in
                        requestAction(.moveFile(file.path))
                    }, statisticsError: diff.statisticsErrorMessage, retryStatistics: diff.retryStatistics)
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
        .sheet(item: $diff.organization) { input in
            if let logSession {
                let log = logSession.log
                RevisionOrganizationSheet(
                    input: input,
                    files: diff.files(for: input.request),
                    selection: diff.splitSelection,
                    revisions: log?.revisions ?? [],
                    hasMatchingSnapshot: log?.operationID == input.request.operationID,
                    busy: diff.isOrganizing,
                    loading: logSession.isLoadingMore,
                    loadRemaining: {
                        guard let log, log.operationID == input.request.operationID else { return }
                        await logSession.loadRemainingPages(in: log.snapshotID)
                    },
                    cancel: { diff.organization = nil },
                    confirm: { destination, paths in
                        Task { await diff.performOrganization(input, destination: destination, paths: paths, log: logSession) }
                    },
                )
            }
        }
        .onDisappear {
            diff.organization = nil
            diff.selectRevision(nil)
        }
    }

    private var fileContent: some View {
        VStack(spacing: 0) {
            if let conflict = diff.files.first(where: \.hasConflict) {
                HStack {
                    Menu {
                        ForEach(diff.files.filter(\.hasConflict)) { file in
                            Button {
                                diff.selectFile(file.path)
                            } label: {
                                Text(verbatim: file.path)
                            }
                        }
                    } label: {
                        Label(I18n.diffConflicts, systemImage: "exclamationmark.triangle")
                    }

                    let file = diff.displayedFile.flatMap { $0.hasConflict ? $0 : nil } ?? conflict
                    Text(verbatim: file.path)
                        .lineLimit(1)

                    Spacer()

                    Button(I18n.organizeResolve) {
                        requestAction(.resolveFile(file.path))
                    }
                    .disabled(revision?.isImmutable != false || diff.isOrganizing || diff.isLoading)
                }
                .padding(8)

                Divider()
            }

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

    private func requestAction(_ action: RevisionOrganizationAction) {
        guard let revision, let request, !diff.isLoading else { return }
        switch action {
        case let .moveFile(path), let .resolveFile(path):
            guard diff.files(for: request).contains(where: { $0.path == path }) else { return }
        default: break
        }
        diff.requestOrganization(action, source: revision, request: request)
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
