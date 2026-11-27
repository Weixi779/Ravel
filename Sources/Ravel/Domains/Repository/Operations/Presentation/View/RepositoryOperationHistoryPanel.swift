//
//  RepositoryOperationHistoryPanel.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Localization
import SwiftUI

struct RepositoryOperationHistoryPanel: View {
    let load: () async throws -> RepositoryOperationHistory
    let undo: (RepositoryOperationHistory) async throws -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var history: RepositoryOperationHistory?
    @State private var isBusy = false
    @State private var problem: String?
    @State private var confirmingUndo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(I18n.repositoryOperations)
                    .font(.headline)

                Spacer()

                Button(I18n.commonRefresh) {
                    Task {
                        await reload()
                    }
                }
                .disabled(isBusy)
            }

            if let problem {
                Text(verbatim: problem)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            List(history?.entries ?? []) { operation in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: operation.description)
                        .textSelection(.enabled)

                    HStack {
                        Text(verbatim: String(operation.id.prefix(12)))
                            .monospaced()

                        Text(operation.date, format: .dateTime)

                        if let workspace = operation.workspace {
                            Text(verbatim: workspace)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(I18n.repositoryUndoLocal) {
                    confirmingUndo = true
                }
                .disabled(isBusy || history?.undoTarget == nil)

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button(I18n.repositoryDismiss) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 340)
        .task {
            await reload()
        }
        .confirmationDialog(I18n.repositoryUndoLocal, isPresented: $confirmingUndo, presenting: history) { confirmed in
            Button(I18n.repositoryUndoLocal, role: .destructive) {
                Task {
                    await undoConfirmed(confirmed)
                }
            }
        } message: { confirmed in
            if let target = confirmed.undoTarget {
                Text(verbatim: target.description + "\n" + target.id)
            }
        }
    }

    private func reload() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            history = try await load()
            problem = nil
        } catch {
            history = nil
            problem = error.localizedDescription
        }
    }

    private func undoConfirmed(_ confirmed: RepositoryOperationHistory) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            problem = try await undo(confirmed)
            history = nil
            history = try await load()
        } catch {
            history = nil
            problem = [problem, error.localizedDescription].compactMap { $0 }.joined(separator: "\n")
        }
    }
}

#if DEBUG
    #Preview("Local operations") {
        @Previewable @State var undone = false
        let entry = RepositoryOperation(id: "8357c6c1b44f", description: "describe commit 4a94fe7", date: .now, workspace: "default")
        RepositoryOperationHistoryPanel(
            load: {
                RepositoryOperationHistory(
                    workspaceURL: URL(fileURLWithPath: "/preview"),
                    headID: entry.id,
                    entries: undone ? [] : [entry],
                    undoTarget: undone ? nil : entry,
                )
            },
            undo: { _ in
                undone = true
                return nil
            },
        )
    }

    #Preview("Load failed") {
        RepositoryOperationHistoryPanel(
            load: { throw CocoaError(.fileReadNoPermission) },
            undo: { _ in nil },
        )
    }
#endif
