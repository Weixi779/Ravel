// Created by weixi on 2026/09/17.

import Foundation

/// Display text and UTF-16 ranges share one mapping; patch control characters never enter code text.
nonisolated struct DiffDisplayDocument: Sendable {
    struct Row: Sendable {
        let line: FileDiff.Line
        let range: NSRange
    }

    let text: String
    let rows: [Row]
    let additions: Int
    let deletions: Int

    init(_ diff: FileDiff) {
        var text = ""
        var rows: [Row] = []
        var offset = 0
        var additions = 0
        var deletions = 0
        for line in diff.lines {
            let value: String
            switch line.kind {
            case .addition, .deletion, .context:
                value = String(line.text.dropFirst())
                if line.kind == .addition { additions += 1 }
                if line.kind == .deletion { deletions += 1 }
            case .hunk:
                // Keep an explicit gap in copied multi-hunk text, rather than pretending it is contiguous source.
                let parts = line.text.split(separator: " ", maxSplits: 4)
                let context = parts.count > 4 ? "  " + parts[4] : ""
                value = "⋯  \(Self.span(parts[1])) → \(Self.span(parts[2]))\(context)"
            case .metadata:
                if line.text.hasPrefix("diff --git ") || line.text.hasPrefix("index ")
                    || line.text.hasPrefix("--- ") || line.text.hasPrefix("+++ ") { continue }
                // Preserve mode/rename information and the missing-final-newline notice.
                value = line.text
            }
            let content = value + "\n"
            let range = NSRange(location: offset, length: content.utf16.count)
            rows.append(Row(line: line, range: range))
            text.append(content)
            offset += range.length
        }
        self.text = text
        self.rows = rows
        self.additions = additions
        self.deletions = deletions
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

    private static func span(_ patchRange: Substring) -> String {
        let parts = patchRange.dropFirst().split(separator: ",")
        guard let start = Int(parts[0]) else { return "—" }
        let count = parts.count > 1 ? Int(parts[1]) ?? 0 : 1
        if count == 0 { return "—" }
        return count == 1 ? "\(start)" : "\(start)–\(start + count - 1)"
    }
}
