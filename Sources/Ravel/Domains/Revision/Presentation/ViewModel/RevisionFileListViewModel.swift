//
//  RevisionFileListViewModel.swift
//  Ravel
//
//  Created by weixi on 2026/09/18.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Observation

nonisolated enum RevisionFileListMode: String, CaseIterable, Sendable {
    case tree, grouped, list
}

@MainActor
@Observable
final class RevisionFileListViewModel {
    enum Selection: Hashable {
        case file(String)
        case directory(String)

        var nodeID: String {
            switch self {
            case let .file(path): "file:" + path
            case let .directory(id): id
            }
        }
    }

    struct VisibleNode: Identifiable {
        let node: ChangedFileNode
        let depth: Int
        var id: String {
            node.id
        }
    }

    var searchText = "" {
        didSet {
            collapsedSearch.removeAll()
            navigationSelection = nil
        }
    }

    var navigationSelection: Selection?
    var selectedDirectoryID: String? {
        guard case let .directory(id) = navigationSelection else { return nil }
        return id
    }

    private(set) var files: [RevisionFilePresentation] = []
    private var collapsedTree: Set<String> = []
    private var collapsedGroups: Set<String> = []
    private var collapsedSearch: Set<String> = []

    func update(files: [RevisionFilePresentation]) {
        self.files = files
        let valid = directoryIDs(ChangedFileNode.tree(files)).union(directoryIDs(ChangedFileNode.grouped(files)))
        collapsedTree.formIntersection(valid)
        collapsedGroups.formIntersection(valid)
        collapsedSearch.formIntersection(valid)
        if let selectedDirectoryID, !valid.contains(selectedDirectoryID) { navigationSelection = nil }
    }

    func visibleNodes(mode: RevisionFileListMode) -> [VisibleNode] {
        let filtered = filteredFiles
        if mode == .list { return filtered.map { VisibleNode(node: ChangedFileNode.leaf($0), depth: 0) } }
        let nodes = mode == .tree ? ChangedFileNode.tree(filtered) : ChangedFileNode.grouped(filtered)
        let collapsed = collapsedDirectories(mode: mode)
        func flatten(_ nodes: [ChangedFileNode], depth: Int) -> [VisibleNode] {
            nodes.flatMap { node in
                [VisibleNode(node: node, depth: depth)] + (collapsed.contains(node.id) ? [] : flatten(node.children, depth: depth + 1))
            }
        }
        return flatten(nodes, depth: 0)
    }

    func isCollapsed(_ id: String, mode: RevisionFileListMode) -> Bool {
        collapsedDirectories(mode: mode).contains(id)
    }

    func toggle(_ id: String, mode: RevisionFileListMode) {
        setCollapsed(!isCollapsed(id, mode: mode), id: id, mode: mode)
    }

    func expandAll() {
        collapsedTree.removeAll()
        collapsedGroups.removeAll()
        collapsedSearch.removeAll()
    }

    func collapseAll(mode: RevisionFileListMode) {
        if !searchText.isEmpty {
            collapsedSearch = directoryIDs(mode == .tree ? ChangedFileNode.tree(filteredFiles) : ChangedFileNode.grouped(filteredFiles))
        } else if mode == .tree { collapsedTree = directoryIDs(ChangedFileNode.tree(files)) }
        else { collapsedGroups = directoryIDs(ChangedFileNode.grouped(files)) }
    }

    func reveal(_ path: String?) {
        guard let path else { return }
        var parent = ""
        for component in path.split(separator: "/").dropLast() {
            parent = parent.isEmpty ? String(component) : parent + "/" + component
            collapsedTree.remove("directory:" + parent)
            collapsedGroups.remove("directory:" + parent)
            collapsedSearch.remove("directory:" + parent)
        }
    }

    /// A folder may own navigation focus while the inspector keeps its current file.
    func adjacent(to selection: Selection?, forward: Bool, mode: RevisionFileListMode) -> Selection? {
        let nodes = visibleNodes(mode: mode)
        let start = index(of: selection, in: nodes) ?? (forward ? -1 : nodes.count)
        var next = start + (forward ? 1 : -1)
        while nodes.indices.contains(next) {
            let node = nodes[next].node
            if let file = node.file { return .file(file.id) }
            if isCollapsed(node.id, mode: mode) { return .directory(node.id) }
            next += forward ? 1 : -1
        }
        return selection
    }

    func collapse(_ selection: Selection?, mode: RevisionFileListMode) -> Selection? {
        guard mode != .list else { return selection }
        let nodes = visibleNodes(mode: mode)
        guard let index = index(of: selection, in: nodes) else { return selection }
        let item = nodes[index]
        if item.node.file == nil, !isCollapsed(item.id, mode: mode) {
            setCollapsed(true, id: item.id, mode: mode)
            return .directory(item.id)
        }
        guard let parent = nodes[..<index].last(where: { $0.depth < item.depth }) else { return selection }
        if item.node.file != nil { setCollapsed(true, id: parent.id, mode: mode) }
        return .directory(parent.id)
    }

    func expand(_ selection: Selection?, mode: RevisionFileListMode) -> Selection? {
        guard mode != .list else { return selection }
        let nodes = visibleNodes(mode: mode)
        guard let index = index(of: selection, in: nodes), nodes[index].node.file == nil else { return selection }
        let item = nodes[index]
        if isCollapsed(item.id, mode: mode) {
            setCollapsed(false, id: item.id, mode: mode)
            return selection
        }
        guard let child = item.node.children.first else { return selection }
        return child.file.map { .file($0.id) } ?? .directory(child.id)
    }

    private func index(of selection: Selection?, in nodes: [VisibleNode]) -> Int? {
        nodes.firstIndex {
            switch selection {
            case let .file(path): $0.node.file?.id == path
            case let .directory(id): $0.id == id
            case nil: false
            }
        }
    }

    private func collapsedDirectories(mode: RevisionFileListMode) -> Set<String> {
        searchText.isEmpty ? (mode == .tree ? collapsedTree : collapsedGroups) : collapsedSearch
    }

    private func setCollapsed(_ collapsed: Bool, id: String, mode: RevisionFileListMode) {
        var directories = collapsedDirectories(mode: mode)
        if collapsed { directories.insert(id) } else { directories.remove(id) }
        if !searchText.isEmpty { collapsedSearch = directories }
        else if mode == .tree { collapsedTree = directories }
        else { collapsedGroups = directories }
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
