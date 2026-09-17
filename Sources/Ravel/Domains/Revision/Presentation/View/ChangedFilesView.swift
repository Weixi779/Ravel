// Created by weixi on 2026/09/17.

import Localization
import SwiftUI

struct ChangedFilesView: View {
    let files: [ChangedFile]
    @Binding var selection: String?
    @Bindable var options: DiffViewOptions
    @State private var collapsedTree: Set<String> = []
    @State private var collapsedGroups: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(I18n.diffChangedFiles).fontWeight(.medium)
                Text(files.count, format: .number).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Toggle(isOn: $options.groupsFiles) {
                    Image(systemName: options.groupsFiles ? "folder" : "list.bullet.indent")
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help(String(localized: options.groupsFiles ? I18n.diffFileTree : I18n.diffFileGroups))
                .accessibilityLabel(String(localized: I18n.diffFileGroups))
                .accessibilityIdentifier("diff.fileGrouping")
            }
            .font(.system(size: 11))
            .padding(.horizontal, 12)
            .frame(height: 30)
            Divider()
            List(selection: $selection) {
                ForEach(visibleNodes) { item in
                    if let file = item.node.file {
                        FileRow(file: file, name: item.node.name)
                            .padding(.leading, CGFloat(item.depth) * 14 + 18)
                            .tag(file.id)
                    } else {
                        Button {
                            if !collapsed.wrappedValue.insert(item.node.id).inserted {
                                collapsed.wrappedValue.remove(item.node.id)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: collapsed.wrappedValue.contains(item.node.id) ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12)
                                Image(systemName: "folder.fill").foregroundStyle(.cyan)
                                Text(item.node.name).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, CGFloat(item.depth) * 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(item.node.path)
                        .accessibilityLabel(item.node.path)
                        .accessibilityValue(String(localized: collapsed.wrappedValue.contains(item.node.id) ? I18n.diffFolderCollapsed : I18n.diffFolderExpanded))
                        .tag(item.node.id)
                    }
                }
                .font(.system(size: 12))
                .listRowSeparator(.hidden)
            }
            .listStyle(.inset)
            // The same paths move between different parents. Recreate native outline rows when the hierarchy changes.
            .id(options.groupsFiles)
            .contextMenu {
                Button(String(localized: I18n.diffExpandFolders)) { collapsed.wrappedValue.removeAll() }
                Button(String(localized: I18n.diffCollapseFolders)) { collapsed.wrappedValue = directoryIDs(nodes) }
            }
        }
        .onChange(of: options.groupsFiles) { _, _ in
            guard let selection else { return }
            let ancestors = selection.split(separator: "/").dropLast()
            var path = ""
            for component in ancestors {
                path = path.isEmpty ? String(component) : path + "/" + component
                collapsed.wrappedValue.remove("directory:" + path)
            }
        }
    }

    private var collapsed: Binding<Set<String>> {
        options.groupsFiles ? $collapsedGroups : $collapsedTree
    }

    private var nodes: [ChangedFileNode] {
        options.groupsFiles ? ChangedFileNode.grouped(files) : ChangedFileNode.tree(files)
    }

    private struct VisibleNode: Identifiable {
        let node: ChangedFileNode
        let depth: Int
        var id: String {
            node.id
        }
    }

    private var visibleNodes: [VisibleNode] {
        func flatten(_ nodes: [ChangedFileNode], depth: Int) -> [VisibleNode] {
            nodes.flatMap { node in
                [VisibleNode(node: node, depth: depth)] + (collapsed.wrappedValue.contains(node.id) ? [] : flatten(node.children, depth: depth + 1))
            }
        }
        return flatten(nodes, depth: 0)
    }

    private func directoryIDs(_ nodes: [ChangedFileNode]) -> Set<String> {
        Set(nodes.filter { $0.file == nil }.map(\.id)).union(nodes.flatMap { directoryIDs($0.children) })
    }
}

private struct FileRow: View {
    let file: ChangedFile
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            ChangedFileStatusIcon(status: file.status)
                .frame(width: 16)
            Image(systemName: name.hasSuffix(".swift") ? "swift" : "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
        .listRowSeparator(.hidden)
        .help(file.displayPath)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: I18n.diffFileHelp(String(localized: file.status.localizedName), file.displayPath)))
        .contextMenu {
            Button(String(localized: I18n.diffCopyPath)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
        }
    }
}

struct ChangedFileStatusIcon: View {
    let status: ChangedFile.Status

    var body: some View {
        Image(systemName: status.symbolName)
            .foregroundStyle(status.color)
            .help(String(localized: status.localizedName))
            .accessibilityLabel(String(localized: status.localizedName))
    }
}

extension ChangedFile.Status {
    var color: Color {
        switch self {
        case .added: .green
        case .removed: .red
        case .modified: .orange
        case .copied, .renamed: .teal
        }
    }

    var symbolName: String {
        switch self {
        case .added: "plus.circle.fill"
        case .removed: "minus.circle.fill"
        case .modified: "pencil.circle.fill"
        case .copied: "doc.on.doc"
        case .renamed: "arrow.right.circle.fill"
        }
    }
}
