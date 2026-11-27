//
//  RevisionDiff.swift
//  Ravel
//
//  Created by weixi on 2026/09/09.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation

nonisolated struct ChangedFile: Identifiable, Hashable, Sendable {
    enum Status: Sendable {
        case modified, added, removed, copied, renamed, unchanged
    }

    let path: String
    let sourcePath: String
    let status: Status
    var before: FileMetadata?
    var after: FileMetadata?
    var id: String {
        path
    }
}

nonisolated struct FileMetadata: Hashable, Sendable {
    enum Kind: Sendable { case file, symlink, directory, submodule, conflict }
    let kind: Kind
    let executable: Bool?
    let conflictSides: Int
}

nonisolated struct RevisionDiff: Sendable {
    let files: [ChangedFile]
}

nonisolated struct FileChangeStatistics: Equatable, Sendable {
    let additions: Int?
    let deletions: Int?
    let bytesDelta: Int
    var isBinary: Bool {
        additions == nil || deletions == nil
    }
}

nonisolated struct RevisionDiffStatistics: Sendable {
    let files: [String: FileChangeStatistics]
    let additions: Int
    let deletions: Int
    let binaryFiles: Int
}

nonisolated struct FileDiff: Identifiable, Sendable {
    struct Hunk: Hashable, Sendable {
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
    }

    struct Line: Sendable {
        enum Kind: Sendable { case metadata, hunk, context, addition, deletion }
        let text: String
        let kind: Kind
        let oldNumber: Int?
        let newNumber: Int?
        var hunk: Hunk?
    }

    enum Failure: Error {
        case malformedPatch
        case tooLarge
    }

    let id = UUID()
    let lines: [Line]
    let isBinary: Bool
}
