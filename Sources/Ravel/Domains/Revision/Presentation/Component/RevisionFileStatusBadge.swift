//
//  RevisionFileStatusBadge.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Localization
import SwiftUI

struct RevisionFileStatusBadge: View {
    let status: RevisionFilePresentation.Status

    var body: some View {
        symbol
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(status.color)
            .frame(width: 16, height: 16)
            .background(status.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .help(status.localizedName)
            .accessibilityLabel(status.localizedName)
    }

    @ViewBuilder private var symbol: some View {
        switch status {
        case .added:
            Image(systemName: "plus")
        case .removed:
            Image(systemName: "minus")
        case .modified:
            Text(verbatim: "M")
        case .renamed:
            Image(systemName: "arrow.right")
        case .copied:
            Image(systemName: "doc.on.doc")
        case .unchanged:
            Image(systemName: "circle")
        }
    }
}

#if DEBUG
    #Preview("File status badges") {
        HStack(spacing: 10) {
            ForEach(RevisionFilePresentation.Status.allCases, id: \.self) { status in
                RevisionFileStatusBadge(status: status)
            }
        }
        .padding(16)
    }
#endif
