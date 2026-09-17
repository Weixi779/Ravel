// Created by weixi on 2026/09/18.

import AppKit
import Foundation
@testable import Ravel
import SwiftUI
import Testing
import UserDefaultsKit

@MainActor
struct RevisionInspectorRenderingTests {
    @Test(arguments: [false, true], [800.0, 1200.0])
    func inspectorKeepsItsReaderWhileChangingFileNavigation(sideBySide: Bool, width: Double) async throws {
        let suite = "RavelInspectorTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let options = DiffViewOptions(store: UserDefaultsStore(defaults: defaults))
        options.sideBySide = sideBySide
        let files = Self.files
        let patch = Self.patch
        let session = RevisionChangesSession(loader: { _ in RevisionDiff(files: files) }, fileLoader: { _, _ in
            try RevisionPatchParser.parse(patch)
        }, statisticsLoader: { _ in
            RevisionDiffStatistics(files: Dictionary(uniqueKeysWithValues: files.map {
                ($0.path, FileChangeStatistics(additions: $0.status == .removed ? 0 : 8, deletions: $0.status == .added ? 0 : 3, bytesDelta: 60))
            }), additions: 72, deletions: 21, binaryFiles: 0)
        })
        let request = RevisionDiffRequest(repositoryURL: URL(fileURLWithPath: "/Ravel"), commitID: "sample", operationID: "fixed")
        let host = NSHostingView(rootView: RevisionInspectorView(revision: revision("sample"), request: request, diff: session).environment(options))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFront(nil)
        defer { session.selectRevision(nil); window.close() }
        host.layoutSubtreeIfNeeded()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while session.fileDiff == nil || session.summary.additions == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
            host.layoutSubtreeIfNeeded()
        }
        #expect(session.fileDiff != nil)
        #expect(session.summary.additions == 72)
        let contentID = session.fileDiff?.id
        for mode in RevisionFileListMode.allCases {
            options.fileListMode = mode
            host.layoutSubtreeIfNeeded()
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            let table = try #require(descendant(NSTableView.self, in: host))
            #expect(table.numberOfRows >= files.count)
            #expect(table.selectedRow >= 0)
            #expect(session.fileDiff?.id == contentID)
            window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            if let directory = ProcessInfo.processInfo.environment["RAVEL_RENDER_OUTPUT"],
               let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)
            {
                host.cacheDisplay(in: host.bounds, to: image)
                try image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("ravel-inspector-\(mode.rawValue)-\(sideBySide ? "split" : "unified")\(width < 1000 ? "-compact" : "").png"))
            }
        }
    }

    private static var files: [ChangedFile] {
        let regular = FileMetadata(kind: .file, executable: false, conflictSides: 0)
        return [
            ChangedFile(path: "Sources/Revision/RevisionView.swift", sourcePath: "Sources/Revision/RevisionView.swift", status: .modified, before: regular, after: regular),
            ChangedFile(path: "Sources/Revision/RevisionViewModel.swift", sourcePath: "Sources/Revision/RevisionViewModel.swift", status: .added, after: regular),
            ChangedFile(path: "Sources/Legacy/Reader.swift", sourcePath: "Sources/Legacy/Reader.swift", status: .removed, before: regular),
            ChangedFile(path: "Documentation/Reader.md", sourcePath: "Docs/Reader.md", status: .renamed, before: regular, after: regular),
            ChangedFile(path: "Backend/src/diff.rs", sourcePath: "Backend/src/diff.rs", status: .modified, before: regular, after: regular),
            ChangedFile(path: "Configuration/theme.json", sourcePath: "Configuration/theme.json", status: .modified, before: regular, after: regular),
            ChangedFile(path: "Configuration/settings.toml", sourcePath: "Configuration/settings.toml", status: .added, after: regular),
            ChangedFile(path: "Tools/check.sh", sourcePath: "Tools/check.sh", status: .modified, before: regular, after: FileMetadata(kind: .file, executable: true, conflictSides: 0)),
            ChangedFile(path: "Sources/Repository/Session.swift", sourcePath: "Sources/Repository/Session.swift", status: .modified, before: regular, after: FileMetadata(kind: .conflict, executable: nil, conflictSides: 2)),
            ChangedFile(path: "README.md", sourcePath: "README.md", status: .copied, before: regular, after: regular),
        ]
    }

    private static var patch: String {
        let rows = [
            " // Revision changes stay visible while the next snapshot loads.",
            " ", " import SwiftUI", " ", " struct RevisionView: View {", "     var body: some View {",
            "-        Text(\"Loading changes…\")", "+        VStack(alignment: .leading, spacing: 8) {",
            "+            Text(\"Revision changes\")", "+                .font(.headline)", "+        }",
            "     }", " }",
        ]
        let oldCount = rows.count(where: { !$0.hasPrefix("+") })
        let newCount = rows.count(where: { !$0.hasPrefix("-") })
        return "@@ -1,\(oldCount) +1,\(newCount) @@\n" + rows.joined(separator: "\n") + "\n"
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        for child in view.subviews {
            if let result = descendant(type, in: child) { return result }
        }
        return nil
    }
}
