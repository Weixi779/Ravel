//
//  RevisionDirectoryRow.swift
//  Ravel
//
//  Created by weixi on 2026/10/02.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Localization
import SwiftUI

struct RevisionDirectoryRow: View {
    let item: RevisionFileListViewModel.VisibleNode
    let isCollapsed: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Image(systemName: "folder.fill")
                    .foregroundStyle(.cyan)

                Text(verbatim: item.node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(item.depth) * 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.node.path)
        .accessibilityLabel(item.node.path)
        .accessibilityValue(isCollapsed ? I18n.diffFolderCollapsed : I18n.diffFolderExpanded)
        .tag(RevisionFileListViewModel.Selection.directory(item.node.id))
    }
}

#if DEBUG
    #Preview("Directory expansion") {
        @Previewable @State var isCollapsed = false

        RevisionDirectoryRow(item: RevisionFileListPreviewData.directory, isCollapsed: isCollapsed) {
            isCollapsed.toggle()
        }
        .padding()
        .frame(width: 320)
    }
#endif
