//
//  LogGraph.swift
//  Ravel
//
//  Created by weixi on 2026/09/09.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation

nonisolated struct LogGraph: Sendable {
    struct Point: Equatable, Sendable {
        let column: Int
        let fraction: Double
    }

    struct Segment: Equatable, Sendable {
        let start: Point
        let end: Point
        let color: Int
    }

    struct Row: Equatable, Sendable {
        let nodeColumn: Int
        let color: Int
        let segments: [Segment]

        /// Include passing lanes and both ends of a turn before placing the title.
        var occupiedColumn: Int {
            segments.reduce(nodeColumn) { max($0, $1.start.column, $1.end.column) }
        }

        /// A passing or joining edge does not change this node's path identity.
        /// Compare allocated identities, before the renderer wraps them into a palette.
        func isOnPath(_ path: Int) -> Bool {
            color == path
        }
    }

    private struct Lane: Sendable {
        let target: String
        let color: Int
    }

    private(set) var rows: [Row] = []
    private(set) var columnCount = 1
    private var lanes: [Lane?] = []
    private var nextColor = 0

    /// Input stays in jj's child-before-parent order. Continuing paths close
    /// vacant lanes below each node, keeping their relative order and colors.
    init(revisions: [Revision]) throws {
        try append(revisions)
    }

    /// An all-history query keeps pending parent lanes across page boundaries.
    /// Previously emitted rows and colors are never recomputed on append.
    mutating func append(_ revisions: [Revision]) throws {
        for revision in revisions {
            try Task.checkCancellation()
            let incoming = lanes.firstIndex { $0?.target == revision.id }
            let nodeColumn = incoming ?? lanes.firstIndex(where: { $0 == nil }) ?? lanes.count
            let color: Int
            if let incoming, let lane = lanes[incoming] {
                color = lane.color
            } else {
                color = nextColor
                nextColor += 1
            }
            if nodeColumn == lanes.count { lanes.append(nil) }

            var segments: [Segment] = []
            for (column, lane) in lanes.enumerated() {
                guard let lane else { continue }
                segments.append(Segment(
                    start: Point(column: column, fraction: 0),
                    end: Point(column: column, fraction: column == nodeColumn ? 0.5 : 1),
                    color: lane.color,
                ))
            }
            lanes[nodeColumn] = nil

            for (index, parent) in revision.parentIDs.enumerated() {
                let existingColumn = lanes.firstIndex { $0?.target == parent }
                let freeColumn = lanes.firstIndex { $0 == nil }
                let preferredColumn = index == 0 && lanes[nodeColumn] == nil ? nodeColumn : freeColumn
                let column = existingColumn ?? preferredColumn ?? lanes.count
                if column == lanes.count { lanes.append(nil) }

                let edgeColor: Int
                if let existingColumn, let lane = lanes[existingColumn] {
                    edgeColor = lane.color
                } else if index == 0 {
                    edgeColor = color
                } else {
                    edgeColor = nextColor
                    nextColor += 1
                }

                segments.append(Segment(
                    start: Point(column: nodeColumn, fraction: 0.5),
                    end: Point(column: column, fraction: 1),
                    color: edgeColor,
                ))
                if existingColumn == nil {
                    lanes[column] = Lane(target: parent, color: edgeColor)
                }
                columnCount = max(columnCount, column + 1)
            }

            compactLanes(segments: &segments)
            columnCount = max(columnCount, nodeColumn + 1)
            rows.append(Row(nodeColumn: nodeColumn, color: color, segments: segments))
        }
    }

    private mutating func compactLanes(segments: inout [Segment]) {
        var columns: [Int: Int] = [:]
        for column in lanes.indices where lanes[column] != nil {
            columns[column] = columns.count
        }
        guard columns.count < lanes.count else { return }

        segments = segments.flatMap { segment -> [Segment] in
            guard segment.end.fraction == 1,
                  let column = columns[segment.end.column], column != segment.end.column
            else { return [segment] }

            let end = Point(column: column, fraction: 1)
            guard segment.start.fraction == 0 else {
                return [Segment(start: segment.start, end: end, color: segment.color)]
            }

            // Passing paths stay beside the node until its lower half. Only
            // their outgoing ends move, so the preceding row never changes.
            let middle = Point(column: segment.start.column, fraction: 0.5)
            return [
                Segment(start: segment.start, end: middle, color: segment.color),
                Segment(start: middle, end: end, color: segment.color),
            ]
        }
        lanes.removeAll { $0 == nil }
    }
}
