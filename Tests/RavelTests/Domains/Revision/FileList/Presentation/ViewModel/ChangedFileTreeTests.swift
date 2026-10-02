//
//  ChangedFileTreeTests.swift
//  Ravel
//
//  Created by weixi on 2026/10/02.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
@testable import Ravel
import Testing

nonisolated struct ChangedFileTreeTests {
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

    private func file(_ path: String, status: ChangedFile.Status = .modified) -> RevisionFilePresentation {
        RevisionFilePresentation(ChangedFile(path: path, sourcePath: path, status: status))
    }
}
