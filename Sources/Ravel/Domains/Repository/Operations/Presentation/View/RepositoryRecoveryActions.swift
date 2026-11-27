//
//  RepositoryRecoveryActions.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Localization
import SwiftUI

struct RepositoryRecoveryActions: ViewModifier {
    let workspace: RepositoryWorkspace
    let session: LogSession
    @State private var showsOperations = false
    @State private var snapshotInProgress = false
    @State private var message: String?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button(I18n.repositorySnapshot) {
                            snapshot()
                        }
                        .disabled(snapshotInProgress)

                        Button(I18n.repositoryOperations) {
                            showsOperations = true
                        }
                    } label: {
                        Label(I18n.repositoryOperations, systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(session.log == nil || session.isLoading)
                }
            }
            .sheet(isPresented: $showsOperations) {
                if let url = session.log?.repositoryURL {
                    RepositoryOperationHistoryPanel(
                        load: { try await workspace.operationHistory(at: url) },
                        undo: { history in
                            let receipt = try await workspace.undo(history)
                            refreshAfterWrite(receipt, at: url)
                            return receipt.feedback
                        },
                    )
                    .id(url)
                }
            }
            .alert(I18n.repositorySnapshot, isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button(I18n.repositoryDismiss) {
                    message = nil
                }
            } message: {
                Text(verbatim: message ?? "")
            }
            .onChange(of: session.repositoryURL) {
                showsOperations = false
                message = nil
            }
    }

    private func snapshot() {
        guard let url = session.log?.repositoryURL, let id = session.displayedOperationID else { return }
        snapshotInProgress = true
        Task {
            defer { snapshotInProgress = false }
            do {
                let receipt = try await workspace.snapshot(at: url, operationID: id)
                guard session.log?.repositoryURL == url else { return }
                refreshAfterWrite(receipt, at: url)
                message = receipt.feedback
            } catch {
                if session.log?.repositoryURL == url { message = error.localizedDescription }
            }
        }
    }

    private func refreshAfterWrite(_ receipt: RepositoryWriteReceipt, at url: URL) {
        if session.log?.repositoryURL == url, receipt.currentOperationID != session.displayedOperationID { session.refresh() }
    }
}

extension RepositoryWriteReceipt {
    var feedback: String? {
        switch disposition {
        case .succeeded: nil
        case .committedWithSyncFailure: [String(localized: I18n.repositoryCommittedSyncFailure), detail].compactMap { $0 }.joined(separator: "\n")
        default: detail
        }
    }
}
