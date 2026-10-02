//
//  RevisionFileListViewModel+Navigation.swift
//  Ravel
//
//  Created by weixi on 2026/10/02.
//  Copyright © 2026 Ravel. All rights reserved.
//

extension RevisionFileListViewModel {
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
}
