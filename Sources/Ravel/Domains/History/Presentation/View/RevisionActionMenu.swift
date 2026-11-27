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
    static func menu(for row: HistoryRevision, session: LogSession) -> NSMenu {
        let revision = row.revision
        let menu = describe { session.beginDescribe(row) }
        func rewrite(_ action: () -> Void) {
            if revision.isImmutable {
                session.commandNotice = String(localized: I18n.historyImmutableReason(revision.shortChangeID))
            } else {
                action()
            }
        }
        menu.addItem(RevisionMenuAction.item(I18n.historyNewChild) {
            Task { await session.run(.newChild, on: row) }
        })
        menu.addItem(RevisionMenuAction.item(I18n.historyEdit) {
            rewrite { Task { await session.run(.edit, on: row) } }
        })
        menu.addItem(RevisionMenuAction.item(I18n.historyRebase) {
            rewrite { session.commandRequest = .rebase(row) }
        })
        menu.addItem(.separator())
        menu.addItem(RevisionMenuAction.item(I18n.historyCreateBookmark) {
            session.commandRequest = .createBookmark(row)
        })
        for name in revision.localBookmarkNames {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            let commands = NSMenu()
            commands.addItem(RevisionMenuAction.item(I18n.historyMoveBookmark) { session.commandRequest = .moveBookmark(row, name) })
            commands.addItem(RevisionMenuAction.item(I18n.historyDeleteBookmark) { session.commandRequest = .deleteBookmark(row, name) })
            item.submenu = commands
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(RevisionMenuAction.item(I18n.historyCopyChangeID) { copy(revision.changeID) })
        menu.addItem(RevisionMenuAction.item(I18n.historyCopyCommitID) { copy(revision.commitID) })
        return menu
    }

    private static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

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
