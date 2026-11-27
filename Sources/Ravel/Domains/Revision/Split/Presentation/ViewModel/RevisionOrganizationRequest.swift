//
//  RevisionOrganizationRequest.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation

enum RevisionOrganizationAction: Equatable {
    case split, confirmSplit, squash, moveFile(String), resolveFile(String)
}

struct RevisionOrganizationRequest: Identifiable {
    let id = UUID()
    let action: RevisionOrganizationAction
    let source: Revision
    let request: RevisionDiffRequest

    var target: RevisionWriteTarget {
        RevisionWriteTarget(workspaceURL: request.repositoryURL, operationID: request.operationID, commitID: source.id, changeID: source.changeID)
    }
}

extension RevisionChangesSession {
    func requestOrganization(_ action: RevisionOrganizationAction, source: Revision, request: RevisionDiffRequest) {
        guard !isOrganizing, request.commitID == source.id else { return }
        if action != .confirmSplit { endSplit() }
        organization = RevisionOrganizationRequest(action: action, source: source, request: request)
        showsDetails = false
    }
}
