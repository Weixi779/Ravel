//
//  LogGraphTests.swift
//  Ravel
//
//  Created by weixi on 2026/09/09.
//  Copyright © 2026 Ravel. All rights reserved.
//

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

    @Test
    func textClearsPassingLanesAndReturnsAfterBranchesConverge() throws {
        let graph = try LogGraph(revisions: [
            revision("merge", parents: ["left", "right"]),
            revision("left", parents: ["base"]),
            revision("right", parents: ["base"]),
            revision("base", parents: ["root"]), revision("root"),
        ])
        #expect(graph.rows.map(\.occupiedColumn) == [1, 1, 1, 0, 0])
        let rightPath = graph.rows[2].color
        #expect(!graph.rows[0].isOnPath(rightPath))
        #expect(!graph.rows[1].isOnPath(rightPath))
        #expect(graph.rows[2].isOnPath(rightPath))
        #expect(!graph.rows[2].isOnPath(graph.rows[3].color))
    }

    @Test
    func focusDoesNotFollowAnUnrelatedReuseOfAPaletteColor() throws {
        let graph = try LogGraph(revisions: (0 ..< 7).map { revision("root-\($0)") })
        #expect(graph.rows[0].color % 6 == graph.rows[6].color % 6)
        #expect(!graph.rows[6].isOnPath(graph.rows[0].color))
    }

    @Test
    func joiningLeftBranchClosesTheGapAndKeepsPathIdentity() throws {
        let graph = try LogGraph(revisions: [
            revision("feature", parents: ["feature-base"]),
            revision("main", parents: ["main-base"]),
            revision("feature-base", parents: ["main-base"]),
            revision("main-base", parents: ["root"]),
            revision("root"),
        ])
        #expect(graph.rows.map(\.nodeColumn) == [0, 1, 0, 0, 0])
        #expect(graph.rows.map(\.occupiedColumn) == [0, 1, 1, 0, 0])
        let path = graph.rows[1].color
        #expect(graph.rows[2].segments.contains(LogGraph.Segment(
            start: .init(column: 1, fraction: 0.5), end: .init(column: 0, fraction: 1), color: path,
        )))
        #expect(graph.rows[3].color == path)
        #expect(graph.rows[4].isOnPath(path))
        #expect(!graph.rows[2].isOnPath(path))
    }

    @Test
    func endingRootClosesMultiplePassingLanesWithoutConnectingToTheRoot() throws {
        let graph = try LogGraph(revisions: [
            revision("left", parents: ["left-root"]),
            revision("middle", parents: ["middle-base"]),
            revision("right", parents: ["right-base"]),
            revision("left-root"),
            revision("middle-base", parents: ["root"]),
            revision("right-base", parents: ["root"]),
            revision("root"),
        ])
        #expect(graph.rows.map(\.nodeColumn) == [0, 1, 2, 0, 0, 1, 0])
        let ending = graph.rows[3]
        #expect(!ending.segments.contains { $0.start == .init(column: ending.nodeColumn, fraction: 0.5) })
        for column in 1 ... 2 {
            let path = graph.rows[column].color
            #expect(ending.segments.contains(LogGraph.Segment(
                start: .init(column: column, fraction: 0.5), end: .init(column: column - 1, fraction: 1), color: path,
            )))
            #expect(graph.rows[column + 3].isOnPath(path))
        }
        #expect(ending.occupiedColumn == 2)
        #expect(graph.rows[4].occupiedColumn == 1)
    }

    @Test(arguments: 0 ... compactionRevisions.count)
    func compactionProducesTheSameGraphAcrossEveryPageBoundary(split: Int) throws {
        let revisions = Self.compactionRevisions
        let complete = try LogGraph(revisions: revisions)
        var paged = try LogGraph(revisions: Array(revisions.prefix(split)))
        let prefix = paged.rows
        try paged.append(Array(revisions.dropFirst(split)))
        #expect(Array(paged.rows.prefix(split)) == prefix)
        #expect(paged.rows == complete.rows)
        #expect(paged.columnCount == complete.columnCount)
    }

    @Test
    func compactedMergePathsJoinTheNextRowWithoutGapsOrColorChanges() throws {
        let graph = try LogGraph(revisions: Self.compactionRevisions)
        #expect(graph.rows.map(\.nodeColumn) == [0, 1, 2, 0, 0, 1, 0, 0])
        for index in 0 ..< graph.rows.count - 1 {
            let outgoing = graph.rows[index].segments.filter { $0.end.fraction == 1 }
            let incoming = graph.rows[index + 1].segments.filter { $0.start.fraction == 0 }
            #expect(Set(outgoing.map { "\($0.end.column):\($0.color)" })
                == Set(incoming.map { "\($0.start.column):\($0.color)" }))
            let columns = Set(outgoing.map(\.end.column))
            #expect(columns == Set(0 ..< columns.count))
        }
        #expect(graph.rows[1].color == graph.rows[4].color)
        #expect(graph.rows[2].color == graph.rows[5].color)
    }

    private static var compactionRevisions: [Revision] {
        [
            revision("feature", parents: ["feature-base"]),
            revision("main", parents: ["main-base"]),
            revision("side", parents: ["side-base"]),
            revision("feature-base", parents: ["main-base"]),
            revision("main-base", parents: ["tail", "side-base"]),
            revision("side-base", parents: ["tail"]),
            revision("tail", parents: ["root"]),
            revision("root"),
        ]
    }
}
