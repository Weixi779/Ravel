//
//  RevisionPathCopy.swift
//  Ravel
//
//  Created by weixi on 2026/10/02.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit

@MainActor
enum RevisionPathCopy {
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
