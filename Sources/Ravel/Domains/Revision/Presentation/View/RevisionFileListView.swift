//
//  RevisionFileListView.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import DesignSystem
import Localization
import SwiftUI

struct RevisionFileListView: View {
    @Bindable var model: RevisionFileListViewModel
    let summary: RevisionChangeSummary
    @Binding var selection: String?
    @Bindable var options: DiffViewOptions
    var statisticsError: String?
    var retryStatistics: () -> Void = {}
    @FocusState private var isFileListFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 9) {
                HStack(spacing: 7) {
                    Text(I18n.diffChangedFiles)
                        .fontWeight(.medium)

                    Text(summary.fileCount, format: .number)
                        .foregroundStyle(.secondary)

                    RevisionLineStatisticsView(additions: summary.additions, deletions: summary.deletions)

                    Spacer(minLength: 0)

                    if let statisticsError {
                        Button(action: retryStatistics) {
                            Image(systemName: "arrow.clockwise.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(statisticsError)
                        .accessibilityLabel(I18n.diffStatisticsRetry)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) {
                        changeCounts

                        Spacer(minLength: 0)

                        layoutPicker
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        changeCounts

                        HStack {
                            Spacer(minLength: 0)

                            layoutPicker
                        }
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField(text: $model.searchText, prompt: Text(I18n.diffSearchFiles)) {
                        Text(I18n.diffSearchFiles)
                    }
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("diff.fileSearch")

                    if !model.searchText.isEmpty {
                        Button {
                            model.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(I18n.diffClearSearch)
                    }
                }
                .padding(6)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
            }
            .font(.system(size: 11))
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollViewReader { proxy in
                List(selection: $model.navigationSelection) {
                    ForEach(model.visibleNodes(mode: options.fileListMode)) { item in
                        if let file = item.node.file {
                            RevisionFileRow(file: file, showsDirectory: options.fileListMode == .list)
                                .padding(.leading, options.fileListMode == .list ? 0 : CGFloat(item.depth) * 14 + 18)
                                .tag(RevisionFileListViewModel.Selection.file(file.id))
                        } else {
                            directoryRow(item)
                        }
                    }
                    .font(.system(size: 12))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.inset)
                .id(options.fileListMode)
                .focused($isFileListFocused)
                .simultaneousGesture(TapGesture().onEnded {
                    isFileListFocused = true
                })
                .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                    guard press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
                    let mode = options.fileListMode
                    let current = model.navigationSelection
                    switch press.key {
                    case .upArrow: model.navigationSelection = model.adjacent(to: current, forward: false, mode: mode)
                    case .downArrow: model.navigationSelection = model.adjacent(to: current, forward: true, mode: mode)
                    case .leftArrow where mode != .list: model.navigationSelection = model.collapse(current, mode: mode)
                    case .rightArrow where mode != .list: model.navigationSelection = model.expand(current, mode: mode)
                    default: return .ignored
                    }
                    if let target = model.navigationSelection { proxy.scrollTo(target.nodeID) }
                    return .handled
                }
                .overlay {
                    if model.visibleNodes(mode: options.fileListMode).isEmpty, !model.searchText.isEmpty {
                        Text(I18n.diffNoMatchingFiles)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .contextMenu {
                    Button(I18n.diffExpandFolders) {
                        model.expandAll()
                    }

                    Button(I18n.diffCollapseFolders) {
                        model.collapseAll(mode: options.fileListMode)
                    }
                }
            }
        }
        .onChange(of: options.fileListMode) { _, _ in
            model.navigationSelection = selection.map { .file($0) }
            model.reveal(selection)
        }
        .onChange(of: selection, initial: true) { _, path in
            model.navigationSelection = path.map { .file($0) }
        }
        .onChange(of: model.navigationSelection) { _, value in
            if case let .file(path) = value { selection = path }
        }
        .onChange(of: model.searchText) { _, _ in
            model.navigationSelection = selection.map { .file($0) }
        }
    }

    private var changeCounts: some View {
        HStack(spacing: 7) {
            ForEach(RevisionFilePresentation.Status.allCases.filter { $0 != .unchanged }, id: \.self) { status in
                if let count = summary.statusCounts[status], count > 0 {
                    HStack(spacing: 3) {
                        RevisionFileStatusIcon(status: status)

                        Text(count, format: .number)
                            .foregroundStyle(.secondary)
                    }
                    .help(status.localizedName)
                }
            }

            if summary.conflicts > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ChangeTone.conflict.color)
                    .help(I18n.diffConflict)

                Text(summary.conflicts, format: .number)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
    }

    private var layoutPicker: some View {
        Picker(I18n.diffFileList, selection: $options.fileListMode) {
            Image(systemName: "list.bullet.indent")
                .help(I18n.diffFileTree)
                .tag(RevisionFileListMode.tree)

            Image(systemName: "folder")
                .help(I18n.diffFileGroups)
                .tag(RevisionFileListMode.grouped)

            Image(systemName: "list.bullet")
                .help(I18n.diffFileList)
                .tag(RevisionFileListMode.list)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 94)
        .accessibilityIdentifier("diff.fileGrouping")
    }

    private func directoryRow(_ item: RevisionFileListViewModel.VisibleNode) -> some View {
        Button {
            model.toggle(item.node.id, mode: options.fileListMode)
            model.navigationSelection = .directory(item.id)
            isFileListFocused = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.isCollapsed(item.node.id, mode: options.fileListMode) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Image(systemName: "folder.fill")
                    .foregroundStyle(.cyan)

                Text(verbatim: item.node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(item.depth) * 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.node.path)
        .accessibilityLabel(item.node.path)
        .accessibilityValue(model.isCollapsed(item.node.id, mode: options.fileListMode) ? I18n.diffFolderCollapsed : I18n.diffFolderExpanded)
        .tag(RevisionFileListViewModel.Selection.directory(item.node.id))
    }
}
