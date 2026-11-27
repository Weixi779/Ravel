//
//  UserDefaultsObservations.swift
//  Ravel
//
//  Created by weixi on 2026/09/16.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
import Observation
import Synchronization

/// One shared observation identity per store/key, retained for the store's lifetime.
/// Snapshots only filter storage notifications; getters always read UserDefaults itself.
final class UserDefaultsObservations: Sendable {
    private struct Entry {
        let field: Field
        var snapshot: Any?
    }

    private struct State {
        var entries: [String: Entry] = [:]
        var token: (any NSObjectProtocol)?
        var accesses = 0
        var changedKeys: Set<String> = []
    }

    private let reference: DefaultsReference
    private let state = Mutex(State())

    init(reference: DefaultsReference) {
        self.reference = reference
    }

    deinit {
        state.withLock { state in
            if let token = state.token {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    func access(_ name: String) {
        let field = state.withLock { state in
            if let entry = state.entries[name] {
                // Native notification order is unspecified. A reentrant reader may see
                // an intermediate value before our notification callback sees it.
                recordChange(for: name, in: &state)
                return entry.field
            }
            if state.token == nil {
                state.token = NotificationCenter.default.addObserver(
                    forName: UserDefaults.didChangeNotification,
                    object: reference.defaults,
                    queue: nil,
                ) { [weak self] _ in
                    self?.storageDidChange()
                }
            }
            let field = Field()
            state.entries[name] = Entry(
                field: field,
                snapshot: reference.defaults.object(forKey: name),
            )
            return field
        }
        field.access()
    }

    func beginAccess() {
        state.withLock { $0.accesses += 1 }
    }

    func endAccess() {
        let changed = state.withLock { state in
            // Performance: every access (including plain reads) scans all keys ever
            // observed by this store. Cost grows with that count and value-comparison
            // size, not just the key being read. Keep this conservative strategy for
            // our small settings set; any optimization must preserve reentrant changes.
            recordChanges(in: &state)
            state.accesses -= 1
            return takeChangesIfIdle(in: &state)
        }
        changed.forEach { $0.invalidate() }
    }

    private func storageDidChange() {
        let changed = state.withLock { state in
            // Keep intermediate changes even while delivery is deferred. Returning to
            // the initial snapshot does not undo dependencies established in between.
            recordChanges(in: &state)
            return takeChangesIfIdle(in: &state)
        }
        changed.forEach { $0.invalidate() }
    }

    private func recordChanges(in state: inout State) {
        for name in state.entries.keys {
            recordChange(for: name, in: &state)
        }
    }

    private func recordChange(for name: String, in state: inout State) {
        guard let entry = state.entries[name] else { return }
        let value = reference.defaults.object(forKey: name)
        guard !Self.equal(entry.snapshot, value) else { return }
        state.entries[name]?.snapshot = value
        state.changedKeys.insert(name)
    }

    private func takeChangesIfIdle(in state: inout State) -> [Field] {
        guard state.accesses == 0 else { return [] }
        let fields = state.changedKeys.compactMap { state.entries[$0]?.field }
        state.changedKeys.removeAll(keepingCapacity: true)
        return fields
    }

    private static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs as NSNumber, rhs as NSNumber):
            // Foundation considers true, 1 and 1.0 equal, but strict decoding does not.
            UserDefaultsNumberKind(lhs) == UserDefaultsNumberKind(rhs) && lhs.isEqual(rhs)
        case let (lhs as [Any], rhs as [Any]):
            lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { equal($0.0, $0.1) }
        case let (lhs as [String: Any], rhs as [String: Any]):
            lhs.count == rhs.count && lhs.allSatisfy { equal($0.value, rhs[$0.key]) }
        case let (lhs as NSObject, rhs as NSObject): lhs.isEqual(rhs)
        default: false
        }
    }

    /// Observation tracks this reference, not a copy of the preference in each model.
    private final class Field: Observable, Sendable {
        private let registrar = ObservationRegistrar()
        private var signal: Void {
            ()
        }

        func access() {
            registrar.access(self, keyPath: \.signal)
        }

        func invalidate() {
            // The external storage has already changed. Invalidate readers without
            // writing the value back, which would produce a notification loop.
            registrar.withMutation(of: self, keyPath: \.signal) {}
        }
    }
}
