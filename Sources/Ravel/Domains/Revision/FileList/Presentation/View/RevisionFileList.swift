//
//  RevisionFileList.swift
//  Ravel
//
//  Created by weixi on 2026/10/02.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Localization
import SwiftUI

struct RevisionFileList: View {
    @Bindable var model: RevisionFileListViewModel
    @Binding var selection: String?
    let mode: RevisionFileListMode
    @FocusState private var isFileListFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $model.navigationSelection) {
                ForEach(model.visibleNodes(mode: mode)) { item in
                    if let file = item.node.file {
                        RevisionFileRow(file: file, showsDirectory: mode == .list)
                            .padding(.leading, mode == .list ? 0 : CGFloat(item.depth) * 14 + 18)
                            .tag(RevisionFileListViewModel.Selection.file(file.id))
                    } else {
                        RevisionDirectoryRow(item: item, isCollapsed: model.isCollapsed(item.id, mode: mode)) {
                            model.toggle(item.id, mode: mode)
                            model.navigationSelection = .directory(item.id)
                            isFileListFocused = true
                        }
                    }
                }
                .font(.system(size: 12))
                .listRowSeparator(.hidden)
            }
            .listStyle(.inset)
            .id(mode)
            .focused($isFileListFocused)
            .simultaneousGesture(TapGesture().onEnded {
                isFileListFocused = true
            })
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                guard press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
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
                if model.visibleNodes(mode: mode).isEmpty, !model.searchText.isEmpty {
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
                    model.collapseAll(mode: mode)
                }
            }
        }
        .onChange(of: mode) { _, _ in
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
}

#if DEBUG
    #Preview("Tree navigation") {
        @Previewable @State var model = RevisionFileListPreviewData.makeModel()
        @Previewable @State var selection: String? = RevisionFileListPreviewData.files.first?.id

        RevisionFileList(model: model, selection: $selection, mode: .tree)
            .frame(width: 360, height: 360)
    }

    #Preview("Filename list") {
        @Previewable @State var model = RevisionFileListPreviewData.makeModel()
        @Previewable @State var selection: String?

        RevisionFileList(model: model, selection: $selection, mode: .list)
            .frame(width: 360, height: 360)
    }
#endif
