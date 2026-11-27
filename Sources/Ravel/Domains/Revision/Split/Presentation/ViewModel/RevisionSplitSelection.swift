//
//  RevisionSplitSelection.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
import Observation

/// A selection belongs to one immutable read view. Only repository paths and original patch
/// coordinates cross the writer boundary. Rendered strings, UTF-16 offsets and row indices do not.
@MainActor
@Observable
final class RevisionSplitSelection {
    enum Portion: Equatable {
        case file
        case hunks(Set<FileDiff.Hunk>)
    }

    let source: Revision
    let request: RevisionDiffRequest
    private(set) var first: [String: Portion] = [:]
    private let changedPaths: Set<String>

    init(source: Revision, request: RevisionDiffRequest, files: [ChangedFile]) {
        self.source = source
        self.request = request
        changedPaths = Set(files.filter { $0.status != .unchanged }.map(\.path))
    }

    var canSplit: Bool {
        !first.isEmpty && (first.count < changedPaths.count || first.values.contains { $0 != .file })
    }

    func setFile(_ path: String, included: Bool) {
        guard changedPaths.contains(path) else { return }
        first[path] = included ? .file : nil
    }

    func includes(_ hunk: FileDiff.Hunk, in path: String) -> Bool {
        switch first[path] {
        case .file: true
        case let .hunks(selected): selected.contains(hunk)
        case nil: false
        }
    }

    func setHunk(_ hunk: FileDiff.Hunk, included: Bool, in path: String, available: [FileDiff.Hunk]) {
        guard changedPaths.contains(path), available.contains(hunk) else { return }
        var selected: Set<FileDiff.Hunk> = switch first[path] {
        case .file: Set(available)
        case let .hunks(value): value
        case nil: []
        }
        if included { selected.insert(hunk) } else { selected.remove(hunk) }
        if selected.isEmpty { first[path] = nil }
        else if selected.count == available.count { first[path] = .file }
        else { first[path] = .hunks(selected) }
    }
}
