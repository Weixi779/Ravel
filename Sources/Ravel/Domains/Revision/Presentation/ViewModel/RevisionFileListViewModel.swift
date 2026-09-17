// Created by weixi on 2026/09/18.

import Foundation
import Observation

nonisolated enum RevisionFileListMode: String, CaseIterable, Sendable {
    case tree, grouped, list
}

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

    var searchText = ""
    private(set) var files: [RevisionFilePresentation] = []
    private var collapsedTree: Set<String> = []
    private var collapsedGroups: Set<String> = []

    func update(files: [RevisionFilePresentation]) {
        self.files = files
        let valid = directoryIDs(ChangedFileNode.tree(files)).union(directoryIDs(ChangedFileNode.grouped(files)))
        collapsedTree.formIntersection(valid)
        collapsedGroups.formIntersection(valid)
    }

    func visibleNodes(mode: RevisionFileListMode) -> [VisibleNode] {
        let filtered = filteredFiles
        if mode == .list { return filtered.map { VisibleNode(node: ChangedFileNode.leaf($0), depth: 0) } }
        let nodes = mode == .tree ? ChangedFileNode.tree(filtered) : ChangedFileNode.grouped(filtered)
        let collapsed = mode == .tree ? collapsedTree : collapsedGroups
        func flatten(_ nodes: [ChangedFileNode], depth: Int) -> [VisibleNode] {
            nodes.flatMap { node in
                [VisibleNode(node: node, depth: depth)] + (searchText.isEmpty && collapsed.contains(node.id) ? [] : flatten(node.children, depth: depth + 1))
            }
        }
        return flatten(nodes, depth: 0)
    }

    func isCollapsed(_ id: String, mode: RevisionFileListMode) -> Bool {
        searchText.isEmpty && (mode == .tree ? collapsedTree : collapsedGroups).contains(id)
    }

    func toggle(_ id: String, mode: RevisionFileListMode) {
        if mode == .tree {
            if !collapsedTree.insert(id).inserted { collapsedTree.remove(id) }
        } else {
            if !collapsedGroups.insert(id).inserted { collapsedGroups.remove(id) }
        }
    }

    func expandAll() {
        collapsedTree.removeAll()
        collapsedGroups.removeAll()
    }

    func collapseAll(mode: RevisionFileListMode) {
        if mode == .tree { collapsedTree = directoryIDs(ChangedFileNode.tree(files)) }
        else { collapsedGroups = directoryIDs(ChangedFileNode.grouped(files)) }
    }

    func reveal(_ path: String?) {
        guard let path else { return }
        var parent = ""
        for component in path.split(separator: "/").dropLast() {
            parent = parent.isEmpty ? String(component) : parent + "/" + component
            collapsedTree.remove("directory:" + parent)
            collapsedGroups.remove("directory:" + parent)
        }
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
