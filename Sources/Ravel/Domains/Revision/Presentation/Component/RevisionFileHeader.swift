// Created by weixi on 2026/09/18.

import DesignSystem
import Localization
import SwiftUI

struct RevisionFileHeader: View {
    let file: RevisionFilePresentation
    let repositoryURL: URL?
    let isLoading: Bool
    let canSearch: Bool
    @Bindable var options: DiffViewOptions
    @Binding var showsInformation: Bool
    var find: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                RevisionFileStatusIcon(status: file.status)

                FileTypeIcon(fileName: file.name)

                Text(verbatim: file.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Button {
                    RevisionPathCopy.copy(file.path)
                } label: {
                    Image(systemName: "link")
                }
                .help(I18n.diffCopyPath)
                .accessibilityLabel(I18n.diffCopyPath)
                .accessibilityIdentifier("diff.copyPath")

                Button {
                    RevisionPathCopy.copy(file.name)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help(I18n.diffCopyName)
                .accessibilityLabel(I18n.diffCopyName)
                .accessibilityIdentifier("diff.copyName")

                RevisionFileAttributes(file: file)

                Spacer(minLength: 4)

                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .help(I18n.diffLoading)
                }

                Button {
                    showsInformation.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .help(I18n.diffFileInformation)
                .accessibilityLabel(I18n.diffFileInformation)
                .popover(isPresented: $showsInformation) {
                    RevisionFileInformation(file: file)
                }

                Toggle(isOn: $options.sideBySide) {
                    Image(systemName: options.sideBySide ? "rectangle.split.1x2" : "rectangle.split.2x1")
                }
                .toggleStyle(.button)
                .help(options.sideBySide ? I18n.diffUnified : I18n.diffSideBySide)
                .accessibilityLabel(I18n.diffSideBySide)
                .accessibilityIdentifier("diff.sideBySide")

                Button(action: find) {
                    Image(systemName: "magnifyingglass")
                }
                .disabled(!canSearch)
                .help(I18n.diffFind)
                .accessibilityLabel(I18n.diffFind)
            }
            .buttonStyle(.borderless)

            HStack {
                Text(verbatim: file.displayPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(file.displayPath)

                Spacer(minLength: 0)

                if let statistics = file.statistics {
                    RevisionLineStatisticsView(additions: statistics.additions, deletions: statistics.deletions)
                }
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(file.status.color.opacity(0.05))
        .contextMenu {
            Button(I18n.diffCopyPath) {
                RevisionPathCopy.copy(file.path)
            }

            Button(I18n.diffCopyName) {
                RevisionPathCopy.copy(file.name)
            }

            if let repositoryURL {
                Button(I18n.diffCopyAbsolutePath) {
                    RevisionPathCopy.copy(repositoryURL.appendingPathComponent(file.path).path)
                }
            }
        }
    }
}

private struct RevisionFileInformation: View {
    let file: RevisionFilePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: file.name)
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Color.clear
                        .frame(width: 1, height: 1)

                    Text(I18n.diffBefore)
                        .foregroundStyle(.secondary)

                    Text(I18n.diffAfter)
                        .foregroundStyle(.secondary)
                }

                GridRow {
                    Text(I18n.diffType)

                    Text(kind(file.before))

                    Text(kind(file.after))
                }

                GridRow {
                    Text(I18n.diffMode)

                    Text(verbatim: mode(file.before))
                        .monospaced()

                    Text(verbatim: mode(file.after))
                        .monospaced()
                }

                GridRow {
                    Text(I18n.diffConflicts)

                    Text(verbatim: conflict(file.before))

                    Text(verbatim: conflict(file.after))
                }
            }
            .font(.callout)

            Text(verbatim: file.displayPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(minWidth: 280, maxWidth: 420)
    }

    private func kind(_ metadata: RevisionFilePresentation.Metadata?) -> LocalizedStringResource {
        guard let metadata else { return I18n.diffAbsent }
        switch metadata.kind {
        case .file: return I18n.diffRegularFile
        case .directory: return I18n.diffDirectory
        case .symlink: return I18n.diffSymbolicLink
        case .submodule: return I18n.diffSubmodule
        case .conflict: return I18n.diffConflict
        }
    }

    private func mode(_ metadata: RevisionFilePresentation.Metadata?) -> String {
        guard let executable = metadata?.executable else { return "—" }
        return executable ? "100755" : "100644"
    }

    private func conflict(_ metadata: RevisionFilePresentation.Metadata?) -> String {
        guard let sides = metadata?.conflictSides, sides > 0 else { return "—" }
        return String(sides)
    }
}
