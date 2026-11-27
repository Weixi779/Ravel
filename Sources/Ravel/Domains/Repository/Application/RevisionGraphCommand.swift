//
//  RevisionGraphCommand.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation

nonisolated enum RevisionGraphCommand: Sendable {
    case newChild
    case edit
    case rebase(destination: RevisionWriteTarget, descendants: Bool)
    case createBookmark(name: String)
    case moveBookmark(name: String, destination: RevisionWriteTarget)
    case deleteBookmark(name: String)
}

nonisolated struct LocalBookmark: Identifiable, Equatable, Sendable {
    let name: String
    let commitIDs: [String]

    var id: String { name }
}
