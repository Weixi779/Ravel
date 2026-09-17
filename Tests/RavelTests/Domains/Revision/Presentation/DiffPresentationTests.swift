// Created by weixi on 2026/09/17.

import Foundation
@testable import Ravel
import Testing

nonisolated struct DiffPresentationTests {
    @Test
    func treeKeepsFullHierarchyAndDistinctFileAndDirectoryIdentities() throws {
        let files = [file("App/Features/UI/Cell.swift"), file("App/Features/UI/Other.swift"),
                     file("README.md"), file("App", status: .removed)]
        let tree = ChangedFileNode.tree(files)
        let app = try #require(tree.first)
        #expect(app.name == "App")
        #expect(app.file == nil)
        let features = try #require(app.children.first)
        #expect(features.name == "Features")
        let ui = try #require(features.children.first)
        #expect(ui.name == "UI")
        #expect(ui.children.map(\.name) == ["Cell.swift", "Other.swift"])
        #expect(Set(tree.map(\.id)).count == 3)
        #expect(tree.first(where: { $0.file?.path == "App" })?.file?.status == .removed)
    }

    @Test
    func groupingKeepsRenameIdentityAndFullParentPath() throws {
        let renamed = RevisionFilePresentation(ChangedFile(path: "App/UI/New.swift", sourcePath: "Legacy/Old.swift", status: .renamed))
        let groups = ChangedFileNode.grouped([renamed, file("App/UI/Second.swift"), file("README.md")])
        let group = try #require(groups.first)
        #expect(group.name == "App/UI")
        // Swift Testing cannot infer the throwing effect of this key-path predicate.
        // swiftformat:disable:next preferKeyPath
        #expect(group.children.allSatisfy { $0.children.isEmpty })
        #expect(group.children.first?.file == renamed)
        #expect(group.children.first?.file?.displayPath == "Legacy/Old.swift → App/UI/New.swift")
        #expect(groups.last?.file?.path == "README.md")
    }

    @Test
    func displayStripsOnlyPatchPrefixAndMapsUTF16IncludingCRLF() throws {
        let diff = try RevisionPatchParser.parse("diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -8,2 +8,2 @@\n---literal\n+++字🙂\r\n keep\r\n")
        let document = DiffDisplayDocument(diff)
        #expect(!document.text.contains("diff --git"))
        #expect(document.text.contains("--literal\n++字🙂\r\nkeep\r\n"))
        #expect(document.additions == 1)
        #expect(document.deletions == 1)
        let added = try #require(document.rows.first { $0.line.kind == .addition })
        #expect(added.line.oldNumber == nil)
        #expect(added.line.newNumber == 8)
        #expect((document.text as NSString).substring(with: added.range) == "++字🙂\r\n")
        #expect(document.row(atUTF16Offset: added.range.location + 3)?.line.kind == .addition)
        #expect(document.row(atUTF16Offset: NSMaxRange(added.range))?.line.newNumber == 9)
        #expect(document.row(atUTF16Offset: document.text.utf16.count) == nil)
    }

    @Test
    func displayKeepsEmptyChangedLinesAndNonTextMetadata() throws {
        let diff = try RevisionPatchParser.parse("@@ -0,0 +1,2 @@\n+\n+tail\n\\ No newline at end of file\n")
        let document = DiffDisplayDocument(diff)
        #expect(document.rows[1].range.length == 1)
        #expect(document.rows[1].line.newNumber == 1)
        #expect(document.text.contains("No newline at end of file"))
        let mode = try DiffDisplayDocument(RevisionPatchParser.parse("diff --git a/a b/a\nold mode 100644\nnew mode 100755\n"))
        #expect(mode.text == "old mode 100644\nnew mode 100755\n")
        #expect(mode.rows.allSatisfy { $0.line.oldNumber == nil && $0.line.newNumber == nil })
    }

    @Test
    func splitProjectionAlignsUnequalChangesAndEmphasizesUnicodeSafely() throws {
        let diff = try RevisionPatchParser.parse("@@ -1,3 +1,4 @@\n keep\n-let café = \"旧🙂\"\n+let café = \"新🙂\"\n+extra\n tail\n")
        let before = DiffDisplayDocument(diff, side: .before)
        let after = DiffDisplayDocument(diff, side: .after)
        #expect(before.rows.count == after.rows.count)
        #expect(before.rows[3].line.kind == .spacer)
        #expect(after.rows[3].line.newNumber == 3)
        #expect(before.rows.last?.line.oldNumber == 3)
        #expect(after.rows.last?.line.newNumber == 4)
        let changed = try #require(after.rows[2].line.emphasis)
        #expect((after.rows[2].line.text as NSString).substring(with: changed) == "新")
    }

    @Test
    func commentsAreColoredWithoutTreatingURLsInsideStringsAsComments() throws {
        let diff = try RevisionPatchParser.parse("@@ -0,0 +1,4 @@\n+let url = \"https://example.com\" // note\n+/* start\n+ nested */ let value = 1\n+let text = \"/* plain */\"\n")
        let document = DiffDisplayDocument(diff, fileName: "Sample.swift")
        let comments = document.commentRanges.map { (document.text as NSString).substring(with: $0) }
        #expect(comments == ["// note", "/* start", " nested */"])
        #expect(DiffDisplayDocument(diff, fileName: "unknown.bin").commentRanges.isEmpty)
    }

    private func file(_ path: String, status: ChangedFile.Status = .modified) -> RevisionFilePresentation {
        RevisionFilePresentation(ChangedFile(path: path, sourcePath: path, status: status))
    }
}
