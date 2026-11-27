//
//  RevisionFilePresentation.swift
//  Ravel
//
//  Created by weixi on 2026/09/18.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation

nonisolated struct RevisionFilePresentation: Identifiable, Hashable, Sendable {
    enum Status: CaseIterable, Sendable { case added, removed, modified, renamed, copied, unchanged }
    enum Kind: Sendable { case file, symlink, directory, submodule, conflict }

    struct Metadata: Hashable, Sendable {
        let kind: Kind
        let executable: Bool?
        let conflictSides: Int

        init(_ value: FileMetadata) {
            kind = switch value.kind {
            case .file: .file
            case .symlink: .symlink
            case .directory: .directory
            case .submodule: .submodule
            case .conflict: .conflict
            }
            executable = value.executable
            conflictSides = value.conflictSides
        }
    }

    let path: String
    let sourcePath: String
    let name: String
    let directory: String
    let status: Status
    let before: Metadata?
    let after: Metadata?
    var statistics: RevisionLineStatistics?
    var id: String {
        path
    }

    var allowsHunkSelection: Bool {
        status == .modified && kind == .file && !hasConflict && !resolvesConflict
            && (before == nil || before?.kind == .file)
    }

    var hasConflict: Bool {
        after?.kind == .conflict
    }

    var resolvesConflict: Bool {
        before?.kind == .conflict && !hasConflict
    }

    var displayPath: String {
        sourcePath == path ? path : "\(sourcePath) → \(path)"
    }

    var kind: Kind {
        (after ?? before)?.kind ?? .file
    }

    var executable: Bool {
        (after ?? before)?.executable == true
    }

    var modeChanged: Bool {
        before?.executable != after?.executable && before != nil && after != nil
    }

    init(_ file: ChangedFile, statistics: FileChangeStatistics? = nil) {
        path = file.path
        sourcePath = file.sourcePath
        name = (file.path as NSString).lastPathComponent
        let parent = (file.path as NSString).deletingLastPathComponent
        directory = parent.isEmpty ? "." : parent
        status = switch file.status {
        case .added: .added
        case .removed: .removed
        case .modified: .modified
        case .renamed: .renamed
        case .copied: .copied
        case .unchanged: .unchanged
        }
        before = file.before.map(Metadata.init)
        after = file.after.map(Metadata.init)
        self.statistics = statistics.map(RevisionLineStatistics.init)
    }
}

nonisolated struct RevisionLineStatistics: Hashable, Sendable {
    let additions: Int?
    let deletions: Int?
    let bytesDelta: Int
    var isBinary: Bool {
        additions == nil || deletions == nil
    }

    init(_ statistics: FileChangeStatistics) {
        additions = statistics.additions
        deletions = statistics.deletions
        bytesDelta = statistics.bytesDelta
    }
}

nonisolated struct RevisionChangeSummary: Sendable {
    let fileCount: Int
    let statusCounts: [RevisionFilePresentation.Status: Int]
    let conflicts: Int
    let additions: Int?
    let deletions: Int?
    let binaryFiles: Int?

    init(files: [RevisionFilePresentation], statistics: RevisionDiffStatistics?) {
        fileCount = files.count
        statusCounts = Dictionary(grouping: files, by: \.status).mapValues(\.count)
        conflicts = files.filter(\.hasConflict).count
        additions = statistics?.additions
        deletions = statistics?.deletions
        binaryFiles = statistics?.binaryFiles
    }
}
