//
//  LogSession+Window.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation

extension LogSession {
    func reconcileWindow(
        checkDisk: Bool,
        focus: Bool,
        paths: [String] = [],
        isFocused: () -> Bool = { true },
        permitted: () -> Bool,
    ) async {
        guard let url = log?.repositoryURL, permitted(), !isSubmitting else { return }
        func stillVisible() -> Bool {
            !Task.isCancelled && self.log?.repositoryURL == url && permitted()
        }
        do {
            await waitForHistoryRefresh()
            guard stillVisible(), let log else { return }
            guard try await !workspace.isWriting(at: url), stillVisible() else { return }
            if focus && isFocused() {
                guard let receipt = try await workspace.snapshotIfIdle(at: url, operationID: log.operationID) else { return }
                guard stillVisible() else { return }
                if let message = HistoryWriteFeedback(receipt).message { commandNotice = message }
            }
            let heads = try await workspace.operationHeads(at: url)
            await waitForHistoryRefresh()
            guard stillVisible(), try await !workspace.isWriting(at: url), stillVisible() else { return }
            let changed = heads.count != 1 || heads.first != self.log?.operationID
            if changed, !isLoading { refresh() }
            if checkDisk || changed {
                let dirty = try await workspace.hasDiskChanges(at: url, paths: hasDiskChanges || changed ? [] : paths)
                guard stillVisible() else { return }
                hasDiskChanges = dirty
            }
        } catch is CancellationError {
        } catch {
            if stillVisible() { commandNotice = error.localizedDescription }
        }
    }

    func snapshotDiskChanges() async {
        guard let log, !isSnapshotting else { return }
        isSnapshotting = true
        defer { isSnapshotting = false }
        do {
            let receipt = try await workspace.snapshot(at: log.repositoryURL, operationID: log.operationID)
            guard self.log?.repositoryURL == log.repositoryURL else { return }
            commandNotice = HistoryWriteFeedback(receipt).message
            if receipt.disposition == .succeeded { hasDiskChanges = false }
            if receipt.currentOperationID != log.operationID { refresh() }
        } catch {
            if self.log?.repositoryURL == log.repositoryURL { commandNotice = error.localizedDescription }
        }
    }
}
