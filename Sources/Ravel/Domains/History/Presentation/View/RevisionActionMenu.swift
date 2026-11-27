//
//  RevisionActionMenu.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit
import Localization

@MainActor
enum RevisionActionMenu {
    static func describe(_ action: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(RevisionMenuAction.item(I18n.historyDescribe, perform: action))
        return menu
    }
}

@MainActor
final class RevisionMenuAction: NSObject {
    private let perform: () -> Void

    private init(perform: @escaping () -> Void) {
        self.perform = perform
    }

    static func item(_ title: LocalizedStringResource, perform: @escaping () -> Void) -> NSMenuItem {
        let action = RevisionMenuAction(perform: perform)
        let item = NSMenuItem(title: String(localized: title), action: #selector(invoke), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        return item
    }

    @objc
    private func invoke() {
        perform()
    }
}
