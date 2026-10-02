//
//  DiffDisplayDocument.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation

/// A display projection owns text ranges, alignment and decoration independently of the domain.
nonisolated struct DiffDisplayDocument: Sendable {
    enum Side: Sendable { case unified, before, after }

    struct Line: Sendable {
        enum Kind: Sendable { case metadata, hunk, context, addition, deletion, spacer }
        let text: String
        let kind: Kind
        let oldNumber: Int?
        let newNumber: Int?
        var emphasis: NSRange?
    }

    struct Row: Sendable {
        let line: Line
        let range: NSRange
    }

    let id: UUID
    let side: Side
    let text: String
    let rows: [Row]
    let additions: Int
    let deletions: Int
    let commentRanges: [NSRange]

    init(_ diff: FileDiff, side: Side = .unified, fileName: String = "") {
        id = diff.id
        self.side = side
        additions = diff.lines.count(where: { $0.kind == .addition })
        deletions = diff.lines.count(where: { $0.kind == .deletion })
        let projected = Self.project(diff.lines, side: side)
        var text = ""
        var rows: [Row] = []
        var offset = 0
        for line in projected {
            let content = line.text + "\n"
            let range = NSRange(location: offset, length: content.utf16.count)
            rows.append(Row(line: line, range: range))
            text.append(content)
            offset += range.length
        }
        self.text = text
        self.rows = rows
        commentRanges = RevisionCommentHighlighter.ranges(in: rows, fileName: fileName)
    }

    func row(atUTF16Offset offset: Int) -> Row? {
        var lower = 0
        var upper = rows.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if NSMaxRange(rows[middle].range) <= offset { lower = middle + 1 }
            else { upper = middle }
        }
        guard lower < rows.count, rows[lower].range.contains(offset) else { return nil }
        return rows[lower]
    }

    private static func project(_ input: [FileDiff.Line], side: Side) -> [Line] {
        var output: [Line] = []
        var index = 0
        while index < input.count {
            let line = input[index]
            if line.kind == .addition || line.kind == .deletion {
                var removed: [Line] = []
                var added: [Line] = []
                let start = index
                while index < input.count, input[index].kind == .addition || input[index].kind == .deletion {
                    let item = convert(input[index])
                    if item.kind == .deletion { removed.append(item) } else { added.append(item) }
                    index += 1
                }
                for pair in 0 ..< min(removed.count, added.count) {
                    let ranges = changedRanges(before: removed[pair].text, after: added[pair].text)
                    removed[pair].emphasis = ranges.0
                    added[pair].emphasis = ranges.1
                }
                if side == .unified {
                    var oldIndex = 0
                    var newIndex = 0
                    for item in input[start ..< index] {
                        if item.kind == .deletion { output.append(removed[oldIndex]); oldIndex += 1 }
                        else { output.append(added[newIndex]); newIndex += 1 }
                    }
                } else {
                    let lines = side == .before ? removed : added
                    let count = max(removed.count, added.count)
                    output.append(contentsOf: lines)
                    output.append(contentsOf: repeatElement(Line(text: "", kind: .spacer, oldNumber: nil, newNumber: nil), count: count - lines.count))
                }
            } else {
                output.append(convert(line))
                index += 1
            }
        }
        return output
    }

    private static func convert(_ line: FileDiff.Line) -> Line {
        let kind: Line.Kind = switch line.kind {
        case .addition: .addition
        case .deletion: .deletion
        case .context: .context
        case .hunk: .hunk
        case .metadata: .metadata
        }
        let text: String
        if let hunk = line.hunk {
            let context = line.text.isEmpty ? "" : "  " + line.text
            text = "⋯  \(span(start: hunk.oldStart, count: hunk.oldCount)) → \(span(start: hunk.newStart, count: hunk.newCount))\(context)"
        } else {
            text = line.text
        }
        return Line(text: text, kind: kind, oldNumber: line.oldNumber, newNumber: line.newNumber)
    }

    /// Emphasize the changed span without splitting a grapheme or doing quadratic work on long lines.
    private static func changedRanges(before: String, after: String) -> (NSRange?, NSRange?) {
        let old = Array(before)
        let new = Array(after)
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              old[old.count - suffix - 1] == new[new.count - suffix - 1]
        {
            suffix += 1
        }
        func range(_ characters: [Character]) -> NSRange? {
            let length = characters.count - prefix - suffix
            guard length > 0, prefix > 0 || suffix > 0 else { return nil }
            return NSRange(location: String(characters.prefix(prefix)).utf16.count,
                           length: String(characters[prefix ..< prefix + length]).utf16.count)
        }
        return (range(old), range(new))
    }

    private static func span(start: Int, count: Int) -> String {
        if count == 0 { return "—" }
        return count == 1 ? "\(start)" : "\(start)–\(start + count - 1)"
    }
}

nonisolated struct RevisionDiffPresentation: Sendable {
    let id: UUID
    let isBinary: Bool
    let unified: DiffDisplayDocument
    let before: DiffDisplayDocument
    let after: DiffDisplayDocument
    let fileName: String

    init(_ diff: FileDiff, fileName: String) {
        id = diff.id
        isBinary = diff.isBinary
        unified = DiffDisplayDocument(diff, fileName: fileName)
        before = DiffDisplayDocument(diff, side: .before, fileName: fileName)
        after = DiffDisplayDocument(diff, side: .after, fileName: fileName)
        self.fileName = fileName
    }

    var estimatedBytes: Int {
        [unified, before, after].reduce(0) { $0 + $1.text.utf16.count * 2 + $1.rows.count * 128 }
    }
}
