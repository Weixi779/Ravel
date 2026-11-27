//
//  RevisionSplitPreviewData.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

#if DEBUG
    import Foundation

    enum RevisionSplitPreviewData {
        static let file = ChangedFile(path: "Settings.swift", sourcePath: "Settings.swift", status: .modified)
        static let presentation = RevisionDiffPresentation(
            try! RevisionPatchParser.parse("""
            @@ -2,1 +2,2 @@
            -let timeout = 5
            +let timeout = 15
            +let retries = 2
            @@ -20,1 +21,1 @@
            -let title = "Draft"
            +let title = "Ready"
            """),
            fileName: file.path,
        )

        static func selection() -> RevisionSplitSelection {
            let source = Revision(commitID: "abcdef", changeID: "sample", parentIDs: [], description: "Settings", author: "", email: "", timestamp: .distantPast, bookmarks: [], isWorkingCopy: true, isImmutable: false, hasConflict: false, isDivergent: false, isEmpty: false)
            let selection = RevisionSplitSelection(source: source, request: .init(repositoryURL: URL(fileURLWithPath: "/preview"), commitID: source.id, operationID: "preview"), files: [file])
            let hunks = presentation.hunks.map(\.range)
            if let first = hunks.first {
                selection.setHunk(first, included: true, in: file.path, available: hunks)
            }
            return selection
        }
    }
#endif
