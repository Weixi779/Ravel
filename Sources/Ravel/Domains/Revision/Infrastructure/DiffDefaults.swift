// Created by weixi on 2026/09/17.

import UserDefaultsKit

extension UserDefaultsKey {
    static var diffShowsChangeMarkers: UserDefaultsKey<Bool?> {
        .init("diffShowsChangeMarkers", default: nil)
    }

    static var diffFileListMode: UserDefaultsKey<String> {
        .init("diffFileListMode", default: "")
    }

    static var diffSideBySide: UserDefaultsKey<Bool> {
        .init("diffSideBySide", default: false)
    }

    static var diffGroupsFiles: UserDefaultsKey<Bool> {
        .init("diffGroupsFiles", default: false)
    }
}
