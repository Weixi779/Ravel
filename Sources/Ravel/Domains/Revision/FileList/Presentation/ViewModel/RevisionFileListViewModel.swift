//
//  RevisionFileListViewModel.swift
//  Ravel
//
//  Created by weixi on 2026/09/18.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
import Observation

@MainActor
@Observable
final class RevisionFileListViewModel {
    struct VisibleNode: Identifiable {
        let node: ChangedFileNode
        let depth: Int
        var id: String {
            node.id
        }
    }

    var searchText = "" {
        didSet {
            expansion.resetSearch()
            navigationSelection = nil
        }
    }

    var navigationSelection: Selection?
    var selectedDirectoryID: String? {
        guard case let .directory(id) = navigationSelection else { return nil }
        return id
    }

    private(set) var files: [RevisionFilePresentation] = []
    private var expansion = RevisionFileListExpansion()

    func update(files: [RevisionFilePresentation]) {
        self.files = files
        let valid = directoryIDs(ChangedFileNode.tree(files)).union(directoryIDs(ChangedFileNode.grouped(files)))
        expansion.retainDirectories(valid)
        if let selectedDirectoryID, !valid.contains(selectedDirectoryID) {
            navigationSelection = nil
        }
    }

    func visibleNodes(mode: RevisionFileListMode) -> [VisibleNode] {
        let filtered = filteredFiles
        if mode == .list {
            return filtered.map { VisibleNode(node: ChangedFileNode.leaf($0), depth: 0) }
        }
        let nodes = mode == .tree ? ChangedFileNode.tree(filtered) : ChangedFileNode.grouped(filtered)
        let collapsed = expansion.collapsedDirectories(mode: mode, searching: !searchText.isEmpty)
        func flatten(_ nodes: [ChangedFileNode], depth: Int) -> [VisibleNode] {
            nodes.flatMap { node in
                [VisibleNode(node: node, depth: depth)] + (collapsed.contains(node.id) ? [] : flatten(node.children, depth: depth + 1))
            }
        }
        return flatten(nodes, depth: 0)
    }

    func isCollapsed(_ id: String, mode: RevisionFileListMode) -> Bool {
        expansion.collapsedDirectories(mode: mode, searching: !searchText.isEmpty).contains(id)
    }

    func toggle(_ id: String, mode: RevisionFileListMode) {
        setCollapsed(!isCollapsed(id, mode: mode), id: id, mode: mode)
    }

    func setCollapsed(_ collapsed: Bool, id: String, mode: RevisionFileListMode) {
        expansion.setCollapsed(collapsed, id: id, mode: mode, searching: !searchText.isEmpty)
    }

    func expandAll() {
        expansion.expandAll()
    }

    func collapseAll(mode: RevisionFileListMode) {
        let files = searchText.isEmpty ? files : filteredFiles
        let nodes = mode == .tree ? ChangedFileNode.tree(files) : ChangedFileNode.grouped(files)
        expansion.collapse(directoryIDs(nodes), mode: mode, searching: !searchText.isEmpty)
    }

    func reveal(_ path: String?) {
        guard let path else { return }
        expansion.reveal(path)
    }

    private var filteredFiles: [RevisionFilePresentation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = query.isEmpty ? files : files.filter {
            $0.path.localizedStandardContains(query) || $0.sourcePath.localizedStandardContains(query)
        }
        return matches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func directoryIDs(_ nodes: [ChangedFileNode]) -> Set<String> {
        Set(nodes.filter { $0.file == nil }.map(\.id)).union(nodes.flatMap { directoryIDs($0.children) })
    }
}
