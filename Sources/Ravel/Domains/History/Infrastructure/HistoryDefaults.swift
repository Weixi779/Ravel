// Created by weixi on 2026/09/17.

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
}
