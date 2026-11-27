//
//  RevisionFileListExpansion.swift
//  Ravel
//
//  Created by weixi on 2026/10/02.
//  Copyright © 2026 Ravel. All rights reserved.
//

struct RevisionFileListExpansion {
    private var tree: Set<String> = []
    private var groups: Set<String> = []
    private var search: Set<String> = []

    func collapsedDirectories(mode: RevisionFileListMode, searching: Bool) -> Set<String> {
        searching ? search : (mode == .tree ? tree : groups)
    }

    mutating func setCollapsed(_ collapsed: Bool, id: String, mode: RevisionFileListMode, searching: Bool) {
        var directories = collapsedDirectories(mode: mode, searching: searching)
        if collapsed {
            directories.insert(id)
        } else {
            directories.remove(id)
        }
        collapse(directories, mode: mode, searching: searching)
    }

    mutating func collapse(_ directories: Set<String>, mode: RevisionFileListMode, searching: Bool) {
        if searching {
            search = directories
        } else if mode == .tree {
            tree = directories
        } else {
            groups = directories
        }
    }

    mutating func retainDirectories(_ valid: Set<String>) {
        tree.formIntersection(valid)
        groups.formIntersection(valid)
        search.formIntersection(valid)
    }

    mutating func resetSearch() {
        search.removeAll()
    }

    mutating func expandAll() {
        tree.removeAll()
        groups.removeAll()
        search.removeAll()
    }

    mutating func reveal(_ path: String) {
        var parent = ""
        for component in path.split(separator: "/").dropLast() {
            parent = parent.isEmpty ? String(component) : parent + "/" + component
            let id = "directory:" + parent
            tree.remove(id)
            groups.remove(id)
            search.remove(id)
        }
    }
}
