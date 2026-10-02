//
//  HistoryDefaults.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import UserDefaultsKit

extension UserDefaultsKey {
    static var lastWorkspacePath: UserDefaultsKey<String?> {
        .init("lastRepositoryPath", default: nil)
    }

    static var recentWorkspacePaths: UserDefaultsKey<[String]> {
        .init("recentRepositoryPaths", default: [])
    }

    static var historyPageSize: UserDefaultsKey<Int> {
        .init("historyPageSize", default: 1000)
    }

    static var historyGraphStyle: UserDefaultsKey<String> {
        .init("historyGraphStyle", default: HistoryGraphStyle.rounded.rawValue)
    }
}
