//
//  RevisionFileStatusIcon.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import Localization
import SwiftUI

struct RevisionFileStatusIcon: View {
    let status: RevisionFilePresentation.Status

    var body: some View {
        Image(systemName: status.symbolName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(status.color)
            .frame(width: 16, height: 16)
            .background(status.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .help(status.localizedName)
            .accessibilityLabel(status.localizedName)
    }
}
