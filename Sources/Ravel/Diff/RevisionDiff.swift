// Created by weixi on 2026/09/09.

import Foundation

nonisolated struct ChangedFile: Decodable, Identifiable, Hashable, Sendable {
    enum Status: String, Decodable, Sendable {
        case modified, added, removed, copied, renamed

        var letter: String {
            switch self {
            case .modified: "M"
            case .added: "A"
            case .removed: "D"
            case .copied: "C"
            case .renamed: "R"
            }
        }
    }

    let path: String
    let sourcePath: String
    let status: Status
    var id: String { path }
    var displayPath: String { sourcePath == path ? path : "\(sourcePath) → \(path)" }
}

nonisolated struct RevisionDiff: Sendable {
    let files: [ChangedFile]
    let warning: String?
}

nonisolated struct FileDiff: Identifiable, Sendable {
    struct Line: Sendable {
        enum Kind: Sendable { case metadata, hunk, context, addition, deletion }
        let text: String
        let kind: Kind
        let oldNumber: Int?
        let newNumber: Int?
    }

    enum Failure: Error {
        case malformedPatch
        case tooLarge
    }

    static let byteLimit = 2 * 1024 * 1024
    static let lineLimit = 20_000
    let id = UUID()
    let lines: [Line]
    let isBinary: Bool
    let warning: String?

    init(patch: String, warning: String? = nil) throws {
        guard patch.utf8.count < Self.byteLimit else { throw Failure.tooLarge }
        var lines: [Line] = []
        var oldNumber = 0
        var newNumber = 0
        var oldRemaining = 0
        var newRemaining = 0
        var binary = false
        // Split on LF alone: Swift's Character treats CRLF as one grapheme.
        var sourceLines = patch.components(separatedBy: "\n")
        if sourceLines.last == "" { sourceLines.removeLast() }
        guard sourceLines.count <= Self.lineLimit else { throw Failure.tooLarge }

        for text in sourceLines {
            try Task.checkCancellation()
            var kind = Line.Kind.metadata
            var left: Int?
            var right: Int?
            if text.hasPrefix("@@ ") {
                guard oldRemaining == 0, newRemaining == 0 else { throw Failure.malformedPatch }
                let parts = text.split(separator: " ", maxSplits: 4)
                guard parts.count >= 4, parts[3] == "@@",
                      let old = Self.hunkRange(parts[1], sign: "-"),
                      let new = Self.hunkRange(parts[2], sign: "+") else { throw Failure.malformedPatch }
                (oldNumber, oldRemaining) = old
                (newNumber, newRemaining) = new
                kind = .hunk
            } else if text.hasPrefix("\\ No newline at end of file") {
                kind = .metadata
            } else if oldRemaining > 0 || newRemaining > 0 {
                switch text.first {
                case " ":
                    guard oldRemaining > 0, newRemaining > 0 else { throw Failure.malformedPatch }
                    kind = .context
                    left = oldNumber; right = newNumber
                    oldNumber += 1; newNumber += 1
                    oldRemaining -= 1; newRemaining -= 1
                case "-":
                    guard oldRemaining > 0 else { throw Failure.malformedPatch }
                    kind = .deletion
                    left = oldNumber; oldNumber += 1; oldRemaining -= 1
                case "+":
                    guard newRemaining > 0 else { throw Failure.malformedPatch }
                    kind = .addition
                    right = newNumber; newNumber += 1; newRemaining -= 1
                default: throw Failure.malformedPatch
                }
            } else if text.hasPrefix("Binary files "), text.hasSuffix(" differ") {
                binary = true
            }
            lines.append(Line(text: text, kind: kind, oldNumber: left, newNumber: right))
        }
        guard oldRemaining == 0, newRemaining == 0 else { throw Failure.malformedPatch }
        self.lines = lines
        self.isBinary = binary
        self.warning = warning
    }

    private static func hunkRange(_ text: Substring, sign: Character) -> (Int, Int)? {
        guard text.first == sign else { return nil }
        let parts = text.dropFirst().split(separator: ",", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let start = Int(parts[0]), start >= 0,
              let count = parts.count == 2 ? Int(parts[1]) : 1, count >= 0,
              start < Int.max - count else { return nil }
        return (start, count)
    }
}
