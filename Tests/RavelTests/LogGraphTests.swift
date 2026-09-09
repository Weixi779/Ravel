// Created by weixi on 2026/09/09.

import Foundation
import Testing
@testable import Ravel

nonisolated struct LogGraphTests {
    @Test func linearHistoryUsesOneContinuousLane() throws {
        let graph = try LogGraph(revisions: [revision("a", parents: ["b"]), revision("b", parents: ["c"]), revision("c")])
        #expect(graph.columnCount == 1)
        #expect(graph.rows.map(\.nodeColumn) == [0, 0, 0])
        #expect(graph.rows[0].segments.first?.end == LogGraph.Point(column: 0, fraction: 1))
        #expect(graph.rows[1].segments.first?.start == LogGraph.Point(column: 0, fraction: 0))
        #expect(graph.rows[2].segments.count == 1)
    }

    @Test func mergeKeepsParallelParentsSeparateUntilTheyConverge() throws {
        let graph = try LogGraph(revisions: [
            revision("merge", parents: ["left", "right"]),
            revision("left", parents: ["base"]),
            revision("right", parents: ["base"]),
            revision("base"),
        ])
        #expect(graph.columnCount == 2)
        #expect(graph.rows[1].nodeColumn != graph.rows[2].nodeColumn)
        #expect(graph.rows[0].segments.count == 2)
        #expect(graph.rows[1].segments.contains { $0.start.column == 1 && $0.end.column == 1 && $0.end.fraction == 1 })
        #expect(graph.rows[2].segments.contains { $0.start.column == 1 && $0.end.column == 0 })
        #expect(graph.rows[3].nodeColumn == 0)
    }

    @Test func hiddenParentsEndAtBoundaryRatherThanConnectingToAnotherHead() throws {
        let graph = try LogGraph(revisions: [revision("tip", parents: ["hidden"]), revision("unrelated")])
        let edge = try #require(graph.rows[0].segments.first)
        #expect(edge.isBoundary)
        #expect(edge.end.fraction < 1)
        #expect(graph.rows[1].segments.isEmpty)
    }

    @Test func divergentChangeIDsRemainDistinctNodes() throws {
        let graph = try LogGraph(revisions: [
            revision("old", change: "same", parents: ["root"]),
            revision("new", change: "same", parents: ["root"]),
            revision("root"),
        ])
        #expect(graph.rows.count == 3)
        #expect(graph.rows[0].nodeColumn != graph.rows[1].nodeColumn)
    }

    @Test func unrelatedRootsDoNotInventAnEdge() throws {
        let graph = try LogGraph(revisions: [revision("one"), revision("two")])
        #expect(graph.rows.allSatisfy { $0.segments.isEmpty })
    }
}

nonisolated func revision(_ id: String, change: String? = nil, parents: [String] = [], workingCopy: Bool = false) -> Revision {
    Revision(
        commitID: id, changeID: change ?? id, parentIDs: parents, description: "Change \(id)",
        author: "weixi", email: "weixi@example.com", timestamp: Date(timeIntervalSince1970: 1_789_000_000),
        bookmarks: [], isWorkingCopy: workingCopy, isImmutable: false, hasConflict: false,
        isDivergent: false, isEmpty: false
    )
}

nonisolated func repositoryLog(_ path: String, revisions: [Revision]) throws -> RepositoryLog {
    try RepositoryLog(
        repositoryURL: URL(fileURLWithPath: path, isDirectory: true), revisions: revisions,
        graph: LogGraph(revisions: revisions), isLimited: false, jjVersion: "jj 0.41.0", warning: nil
    )
}
