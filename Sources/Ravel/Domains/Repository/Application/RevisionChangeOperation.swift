//
//  RevisionChangeOperation.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation

nonisolated enum RevisionFilePortion: Equatable, Sendable {
    case file
    case hunks(Set<FileDiff.Hunk>)
}

nonisolated enum RevisionChangeOperation: Sendable {
    case split(first: [String: RevisionFilePortion])
    case squash(into: RevisionWriteTarget, paths: [String]?)
    case resolve(path: String)
}
