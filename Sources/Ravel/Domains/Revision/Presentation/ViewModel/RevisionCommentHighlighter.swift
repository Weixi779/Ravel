// Created by weixi on 2026/09/18.

import Foundation

/// Conservative comment coloring for common source formats. Unknown types stay plain text.
nonisolated enum RevisionCommentHighlighter {
    private struct State { var blockDepth = 0; var quote: UInt16? }

    static func ranges(in rows: [DiffDisplayDocument.Row], fileName: String) -> [NSRange] {
        let suffix = (fileName as NSString).pathExtension.lowercased()
        let slash = ["swift", "rs", "c", "h", "m", "mm", "cpp", "hpp", "cc", "js", "jsx", "ts", "tsx", "java", "kt", "kts", "go", "cs", "jsonc", "css", "scss"].contains(suffix)
        let hash = ["py", "pyi", "rb", "sh", "bash", "zsh", "fish", "yaml", "yml", "toml", "r", "pl"].contains(suffix)
            || ["Makefile", "Dockerfile", ".gitignore", ".jjignore"].contains(fileName)
        guard slash || hash else { return [] }
        var before = State()
        var after = State()
        var result: [NSRange] = []
        for row in rows {
            if row.line.kind == .hunk { before = State(); after = State(); continue }
            guard row.line.kind != .metadata, row.line.kind != .spacer else { continue }
            var state = row.line.kind == .deletion ? before : after
            let units = Array(row.line.text.utf16)
            var index = 0
            var commentStart: Int? = state.blockDepth > 0 ? 0 : nil
            while index < units.count {
                let value = units[index]
                let next = index + 1 < units.count ? units[index + 1] : 0
                if state.blockDepth > 0 {
                    if value == 42, next == 47 {
                        state.blockDepth -= 1
                        index += 2
                        if state.blockDepth == 0, let start = commentStart {
                            result.append(NSRange(location: row.range.location + start, length: index - start))
                            commentStart = nil
                        }
                        continue
                    }
                    if ["swift", "rs"].contains(suffix), value == 47, next == 42 { state.blockDepth += 1; index += 2; continue }
                } else if let quote = state.quote {
                    if value == 92 { index += 2; continue }
                    if value == quote { state.quote = nil }
                } else if value == 34 || value == 39 || value == 96 {
                    state.quote = value
                } else if (slash && value == 47 && next == 47) || (hash && value == 35) {
                    commentStart = index
                    index = units.count
                    break
                } else if slash, value == 47, next == 42 {
                    commentStart = index
                    state.blockDepth = 1
                    index += 2
                    continue
                }
                index += 1
            }
            if let start = commentStart { result.append(NSRange(location: row.range.location + start, length: units.count - start)) }
            // Single/double quoted literals normally end at the source line; backticks may span lines.
            if state.quote != 96 { state.quote = nil }
            if row.line.kind == .deletion { before = state }
            else if row.line.kind == .addition { after = state }
            else { before = state; after = state }
        }
        return result
    }
}
