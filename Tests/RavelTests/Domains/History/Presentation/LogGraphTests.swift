// Created by weixi on 2026/09/09.

import Foundation
@testable import Ravel
import Testing

nonisolated struct LogGraphTests {
    @Test
    func linearHistoryUsesOneContinuousLane() throws {
        let graph = try LogGraph(revisions: [revision("a", parents: ["b"]), revision("b", parents: ["c"]), revision("c")])
        #expect(graph.columnCount == 1)
        #expect(graph.rows.map(\.nodeColumn) == [0, 0, 0])
        #expect(graph.rows[0].segments.first?.end == LogGraph.Point(column: 0, fraction: 1))
        #expect(graph.rows[1].segments.first?.start == LogGraph.Point(column: 0, fraction: 0))
        #expect(graph.rows[2].segments.count == 1)
    }

    @Test
    func mergeKeepsParallelParentsSeparateUntilTheyConverge() throws {
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

    @Test
    func pendingParentsContinuePastUnrelatedHeads() throws {
        var graph = try LogGraph(revisions: [revision("tip", parents: ["parent"]), revision("unrelated")])
        let edge = try #require(graph.rows[0].segments.first)
        #expect(edge.end.fraction == 1)
        #expect(graph.rows[1].nodeColumn != edge.end.column)
        #expect(graph.rows[1].segments.contains { $0.start.column == edge.end.column && $0.end.column == edge.end.column })
        try graph.append([revision("parent")])
        #expect(graph.rows[2].nodeColumn == edge.end.column)
    }

    @Test
    func divergentChangeIDsRemainDistinctNodes() throws {
        let graph = try LogGraph(revisions: [
            revision("old", change: "same", parents: ["root"]),
            revision("new", change: "same", parents: ["root"]),
            revision("root"),
        ])
        #expect(graph.rows.count == 3)
        #expect(graph.rows[0].nodeColumn != graph.rows[1].nodeColumn)
    }

    @Test
    func pageBoundaryKeepsMergeParentsAndExistingRowsStable() throws {
        let revisions = [revision("merge", parents: ["left", "right"]),
                         revision("left", parents: ["root"]), revision("right", parents: ["root"]), revision("root")]
        var paged = try LogGraph(revisions: Array(revisions.prefix(2)))
        let prefix = paged.rows
        try paged.append(Array(revisions.suffix(2)))
        #expect(Array(paged.rows.prefix(2)) == prefix)
        #expect(try paged.rows == LogGraph(revisions: revisions).rows)
    }

    @Test
    func unrelatedRootsDoNotInventAnEdge() throws {
        let graph = try LogGraph(revisions: [revision("one"), revision("two")])
        // Swift Testing cannot infer the throwing effect of this key-path predicate.
        // swiftformat:disable:next preferKeyPath
        #expect(graph.rows.allSatisfy { $0.segments.isEmpty })
    }
}
