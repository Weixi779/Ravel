//
//  RepositoryPanel.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit
import Localization

@MainActor
enum RepositoryPanel {
    static func open(using session: LogSession) {
        let panel = NSOpenPanel()
        panel.title = String(localized: I18n.repositoryOpenTitle)
        panel.message = String(localized: I18n.repositoryChooseWorkspace)
        panel.prompt = String(localized: I18n.commonOpen)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = session.repositoryURL
        if panel.runModal() == .OK, let url = panel.url { session.open(url) }
    }
}
