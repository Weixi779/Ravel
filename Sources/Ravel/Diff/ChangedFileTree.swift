// Created by weixi on 2026/09/17.

import Foundation

nonisolated struct ChangedFileNode: Identifiable, Sendable {
    let path: String
    let name: String
    let file: ChangedFile?
    let children: [ChangedFileNode]

    var id: String { "\(file == nil ? "directory" : "file"):\(path)" }

    static func tree(_ files: [ChangedFile]) -> [Self] {
        descendants(files, parent: "")
    }

    static func grouped(_ files: [ChangedFile]) -> [Self] {
        let groups = Dictionary(grouping: files) { file in
            file.path.split(separator: "/").dropLast().joined(separator: "/")
        }
        return sorted(groups.flatMap { path, files -> [Self] in
            if path.isEmpty { return files.map(leaf) }
            return [Self(path: path, name: path, file: nil, children: sorted(files.map(leaf)))]
        })
    }

    private static func descendants(_ files: [ChangedFile], parent: String) -> [Self] {
        let prefix = parent.isEmpty ? "" : parent + "/"
        var leaves: [Self] = []
        var folders: [String: [ChangedFile]] = [:]
        for file in files {
            let remainder = file.path.dropFirst(prefix.count)
            if let separator = remainder.firstIndex(of: "/") {
                folders[String(remainder[..<separator]), default: []].append(file)
            } else {
                leaves.append(leaf(file))
            }
        }
        let directories = folders.map { name, children in
            let path = prefix + name
            return Self(path: path, name: name, file: nil, children: descendants(children, parent: path))
        }
        return sorted(directories + leaves)
    }

    private static func leaf(_ file: ChangedFile) -> Self {
        Self(path: file.path, name: String(file.path.split(separator: "/").last ?? ""), file: file, children: [])
    }

    private static func sorted(_ nodes: [Self]) -> [Self] {
        nodes.sorted {
            if ($0.file == nil) != ($1.file == nil) { return $0.file == nil }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
