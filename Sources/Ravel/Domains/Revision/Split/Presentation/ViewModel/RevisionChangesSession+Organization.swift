//
//  RevisionChangesSession+Organization.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
import Localization

extension RevisionChangesSession {
    func performOrganization(_ input: RevisionOrganizationRequest, destination: Revision?, paths: Set<String>? = nil, log: LogSession) async {
        guard input.id == organization?.id, log.repositoryURL == input.request.repositoryURL, !isOrganizing else { return }
        isOrganizing = true
        defer { isOrganizing = false }
        do {
            if input.action == .split {
                try await prepareSplit(input, log: log)
                return
            }
            let operation: RevisionChangeOperation
            switch input.action {
            case .split: return
            case .confirmSplit:
                guard let splitSelection, splitSelection.canSplit, splitSelection.source == input.source else { return }
                operation = .split(first: splitSelection.first)
            case .squash, .moveFile:
                guard let destination, !destination.isImmutable, destination.id != input.source.id,
                      let snapshot = log.log, snapshot.operationID == input.request.operationID,
                      snapshot.revisions.contains(destination) else { return }
                let target = RevisionWriteTarget(workspaceURL: snapshot.repositoryURL, operationID: snapshot.operationID, commitID: destination.id, changeID: destination.changeID)
                let picked: [String]?
                if case let .moveFile(path) = input.action {
                    picked = [path]
                } else if let paths {
                    guard !paths.isEmpty, paths.isSubset(of: Set(files(for: input.request).map(\.path))) else { return }
                    picked = paths.sorted()
                } else {
                    picked = nil
                }
                operation = .squash(into: target, paths: picked)
            case let .resolveFile(path):
                operation = .resolve(path: path)
            }
            let receipt = try await log.workspace.organize(operation, source: input.target)
            dismissOrganization(input)
            guard log.repositoryURL == input.request.repositoryURL else { return }
            let feedback = HistoryWriteFeedback(receipt)
            if receipt.disposition == .staleTarget {
                let preparation = receipt.preparationOperationID == nil ? "" : String(localized: I18n.historyPreparedOnly) + "\n"
                log.commandNotice = preparation + String(localized: I18n.organizeStale)
            } else {
                log.commandNotice = feedback.message
            }
            if feedback.needsRefresh { log.refresh(selecting: feedback.commitID) }
            if receipt.disposition == .succeeded, let id = receipt.commitID, let op = receipt.currentOperationID {
                let result: RevisionDiff
                do {
                    result = try await log.workspace.diff(.init(repositoryURL: input.request.repositoryURL, commitID: id, operationID: op))
                } catch {
                    if log.repositoryURL == input.request.repositoryURL {
                        log.commandNotice = String(localized: I18n.organizeReadBackFailed) + "\n" + error.localizedDescription
                    }
                    return
                }
                guard log.repositoryURL == input.request.repositoryURL else { return }
                let remaining = result.files.filter { $0.after?.kind == .conflict }.map(\.path)
                if !remaining.isEmpty {
                    log.commandNotice = String(localized: I18n.organizeUnresolvedFiles) + "\n" + remaining.joined(separator: "\n")
                } else if case .resolveFile = input.action {
                    log.commandNotice = String(localized: I18n.organizeResolved)
                }
            }
        } catch {
            dismissOrganization(input)
            guard log.repositoryURL == input.request.repositoryURL else { return }
            log.commandNotice = error.localizedDescription
        }
    }

    private func dismissOrganization(_ input: RevisionOrganizationRequest) {
        guard organization?.id == input.id else { return }
        organization = nil
        endSplit()
    }

    private func prepareSplit(_ input: RevisionOrganizationRequest, log: LogSession) async throws {
        var expected = input.source.id
        if input.source.isWorkingCopy {
            let receipt = try await log.workspace.snapshot(at: input.request.repositoryURL, operationID: input.request.operationID)
            guard log.repositoryURL == input.request.repositoryURL, organization?.id == input.id else { return }
            guard receipt.disposition == .succeeded, receipt.changeID == input.source.changeID, let commit = receipt.commitID else {
                dismissOrganization(input)
                let feedback = HistoryWriteFeedback(receipt)
                log.commandNotice = feedback.message ?? String(localized: I18n.organizeStale)
                log.refresh()
                return
            }
            expected = commit
            await log.refreshForSplit(selecting: commit)
        }
        guard organization?.id == input.id else { return }
        guard !log.isLoading, let displayed = log.selectedRevision, displayed.id == expected, let request = log.diffRequest,
              displayed.changeID == input.source.changeID, request.repositoryURL == input.request.repositoryURL,
              displayed.isWorkingCopy == input.source.isWorkingCopy, !displayed.isImmutable else {
            dismissOrganization(input)
            log.commandNotice = String(localized: I18n.organizeStale)
            return
        }
        selectRevision(request, revision: displayed)
        await beginSplitWhenLoaded(displayed, request: request, intentID: input.id)
        guard organization?.id == input.id else { return }
        organization = nil
        if !isSelectingSplit { log.commandNotice = errorMessage ?? String(localized: I18n.organizeCannotSplit) }
    }
}
