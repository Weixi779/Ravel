//
//  RevisionPatchParser.swift
//  Ravel
//
//  Created by weixi on 2026/09/18.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation

/// Converts the backend wire format into content without patch control prefixes.
nonisolated enum RevisionPatchParser {
    static let byteLimit = 2 * 1024 * 1024
    static let lineLimit = 20000

    static func parse(_ patch: String) throws -> FileDiff {
        guard patch.utf8.count < byteLimit else { throw FileDiff.Failure.tooLarge }
        var lines: [FileDiff.Line] = []
        var oldNumber = 0
        var newNumber = 0
        var oldRemaining = 0
        var newRemaining = 0
        var binary = false
        var hunk: FileDiff.Hunk?
        // Split on LF alone: Swift's Character treats CRLF as one grapheme.
        var sourceLines = patch.components(separatedBy: "\n")
        if sourceLines.last == "" { sourceLines.removeLast() }
        guard sourceLines.count <= lineLimit else { throw FileDiff.Failure.tooLarge }

        for text in sourceLines {
            try Task.checkCancellation()
            var kind = FileDiff.Line.Kind.metadata
            var left: Int?
            var right: Int?
            hunk = nil
            var content = text
            if text.hasPrefix("@@ ") {
                guard oldRemaining == 0, newRemaining == 0 else { throw FileDiff.Failure.malformedPatch }
                let parts = text.split(separator: " ", maxSplits: 4)
                guard parts.count >= 4, parts[3] == "@@",
                      let old = Self.hunkRange(parts[1], sign: "-"),
                      let new = Self.hunkRange(parts[2], sign: "+") else { throw FileDiff.Failure.malformedPatch }
                (oldNumber, oldRemaining) = old
                (newNumber, newRemaining) = new
                kind = .hunk
                hunk = FileDiff.Hunk(oldStart: old.0, oldCount: old.1, newStart: new.0, newCount: new.1)
                content = parts.count > 4 ? String(parts[4]) : ""
            } else if text.hasPrefix("\\ No newline at end of file") {
                kind = .metadata
            } else if oldRemaining > 0 || newRemaining > 0 {
                content = String(text.dropFirst())
                switch text.first {
                case " ":
                    guard oldRemaining > 0, newRemaining > 0 else { throw FileDiff.Failure.malformedPatch }
                    kind = .context
                    left = oldNumber; right = newNumber
                    oldNumber += 1; newNumber += 1
                    oldRemaining -= 1; newRemaining -= 1
                case "-":
                    guard oldRemaining > 0 else { throw FileDiff.Failure.malformedPatch }
                    kind = .deletion
                    left = oldNumber; oldNumber += 1; oldRemaining -= 1
                case "+":
                    guard newRemaining > 0 else { throw FileDiff.Failure.malformedPatch }
                    kind = .addition
                    right = newNumber; newNumber += 1; newRemaining -= 1
                default: throw FileDiff.Failure.malformedPatch
                }
            } else if text.hasPrefix("Binary files "), text.hasSuffix(" differ") {
                binary = true
            }
            if kind == .metadata, text.hasPrefix("diff --git ") || text.hasPrefix("index ")
                || text.hasPrefix("--- ") || text.hasPrefix("+++ ") { continue }
            lines.append(FileDiff.Line(text: content, kind: kind, oldNumber: left, newNumber: right, hunk: hunk))
        }
        guard oldRemaining == 0, newRemaining == 0 else { throw FileDiff.Failure.malformedPatch }
        return FileDiff(lines: lines, isBinary: binary)
    }

    private static func hunkRange(_ text: Substring, sign: Character) -> (Int, Int)? {
        guard text.first == sign else { return nil }
        let parts = text.dropFirst().split(separator: ",", omittingEmptySubsequences: false)
        guard (1 ... 2).contains(parts.count), let start = Int(parts[0]), start >= 0,
              let count = parts.count == 2 ? Int(parts[1]) : 1, count >= 0,
              start < Int.max - count else { return nil }
        return (start, count)
    }
}
