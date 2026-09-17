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

    private let store: UserDefaultsStore

    init(store: UserDefaultsStore = .standard) {
        self.store = store
    }
}
