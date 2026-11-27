//
//  RevisionFileListPreviewData.swift
//  Ravel
//
//  Created by weixi on 2026/10/02.
//  Copyright © 2026 Ravel. All rights reserved.
//

#if DEBUG
    @MainActor
    enum RevisionFileListPreviewData {
        static let files = [
            RevisionFilePresentation(
                ChangedFile(path: "Sources/Navigation/FileNavigator.swift", sourcePath: "Sources/Navigation/FileNavigator.swift", status: .modified),
                statistics: FileChangeStatistics(additions: 12, deletions: 4, bytesDelta: 180),
            ),
            RevisionFilePresentation(
                ChangedFile(path: "Tests/NavigationTests.swift", sourcePath: "Tests/NavigationTests.swift", status: .added),
                statistics: FileChangeStatistics(additions: 28, deletions: 0, bytesDelta: 720),
            ),
            RevisionFilePresentation(
                ChangedFile(path: "Legacy/FileBrowser.swift", sourcePath: "Legacy/FileBrowser.swift", status: .removed),
                statistics: FileChangeStatistics(additions: 0, deletions: 18, bytesDelta: -420),
            ),
            RevisionFilePresentation(
                ChangedFile(path: "Sources/Navigation/FileSelection.swift", sourcePath: "Sources/Browser/Selection.swift", status: .renamed),
                statistics: FileChangeStatistics(additions: 4, deletions: 2, bytesDelta: 32),
            ),
            RevisionFilePresentation(
                ChangedFile(path: "Assets/Brand.png", sourcePath: "Assets/Brand.png", status: .modified),
                statistics: FileChangeStatistics(additions: nil, deletions: nil, bytesDelta: 2048),
            ),
            RevisionFilePresentation(
                ChangedFile(
                    path: "Sources/Settings/AppSettings.swift",
                    sourcePath: "Sources/Settings/AppSettings.swift",
                    status: .modified,
                    before: FileMetadata(kind: .file, executable: false, conflictSides: 0),
                    after: FileMetadata(kind: .conflict, executable: nil, conflictSides: 2),
                ),
            ),
        ]

        static let summary = RevisionChangeSummary(
            files: files,
            statistics: RevisionDiffStatistics(files: [:], additions: 44, deletions: 24, binaryFiles: 1),
        )

        static func makeModel(
            files: [RevisionFilePresentation] = RevisionFileListPreviewData.files,
            searchText: String = "",
        ) -> RevisionFileListViewModel {
            let model = RevisionFileListViewModel()
            model.update(files: files)
            model.searchText = searchText
            return model
        }

        static let directory = RevisionFileListViewModel.VisibleNode(
            node: ChangedFileNode(path: "Sources/Navigation", name: "Navigation", file: nil, children: []),
            depth: 1,
        )
    }
#endif
