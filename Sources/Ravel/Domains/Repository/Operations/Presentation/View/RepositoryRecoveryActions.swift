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

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button(I18n.repositorySnapshot) {
                            Task { await session.snapshotDiskChanges() }
                        }
                        .disabled(session.isSnapshotting)

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
            .onChange(of: session.repositoryURL) {
                showsOperations = false
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
