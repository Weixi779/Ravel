//
//  RevisionLineStatisticsView.swift
//  Ravel
//
//  Created by weixi on 2026/09/18.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import DesignSystem
import Localization
import SwiftUI

struct RevisionLineStatisticsView: View {
    let additions: Int?
    let deletions: Int?

    var body: some View {
        HStack(spacing: 6) {
            if let additions, let deletions {
                Text(verbatim: "+\(additions)")
                    .foregroundStyle(ChangeTone.addition.color)
                    .help(I18n.diffLinesAdded)

                Text(verbatim: "−\(deletions)")
                    .foregroundStyle(ChangeTone.deletion.color)
                    .help(I18n.diffLinesRemoved)
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .fixedSize()
    }
}
