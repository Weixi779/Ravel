// Created by weixi on 2026/09/17.

import Observation
import UserDefaultsKit
import UserDefaultsKitMacros

@MainActor
@Observable
final class DiffViewOptions {
    @ObservedDefault(.diffShowsChangeMarkers, store: \Self.store)
    @ObservationIgnored var showsChangeMarkers: Bool?

    @ObservedDefault(.diffGroupsFiles, store: \Self.store)
    @ObservationIgnored var groupsFiles: Bool

    @ObservedDefault(.diffFileListMode, store: \Self.store)
    @ObservationIgnored private var storedFileListMode: String

    @ObservedDefault(.diffSideBySide, store: \Self.store)
    @ObservationIgnored var sideBySide: Bool

    var fileListMode: RevisionFileListMode {
        get { RevisionFileListMode(rawValue: storedFileListMode) ?? (groupsFiles ? .grouped : .tree) }
        set { storedFileListMode = newValue.rawValue }
    }

    private let store: UserDefaultsStore

    init(store: UserDefaultsStore = .standard) {
        self.store = store
    }
}
