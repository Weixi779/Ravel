// Created by weixi on 2026/09/16.

import UserDefaultsKit

/// Group keys by business purpose; each declaration carries its own value type.
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

    static var diffShowsChangeMarkers: UserDefaultsKey<Bool?> {
        .init("diffShowsChangeMarkers", default: nil)
    }

    static var diffGroupsFiles: UserDefaultsKey<Bool> {
        .init("diffGroupsFiles", default: false)
    }
}
