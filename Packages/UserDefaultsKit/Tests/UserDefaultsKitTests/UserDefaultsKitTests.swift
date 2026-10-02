//
//  UserDefaultsKitTests.swift
//  Ravel
//
//  Created by weixi on 2026/09/16.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Dispatch
import Foundation
import Observation
import Synchronization
import Testing
import UserDefaultsKit

struct UserDefaultsKitTests {
    @Test
    func declarationNeedsOnlyATypedKey() {
        // A per-run key exercises the standard store without reading or changing app preferences.
        @UserDefault(.standardTestPath) var path: String?
        defer { _path.reset() }
        #expect(path == nil)
        path = "/workspace"
        #expect(UserDefaults.standard.string(forKey: StandardTestKey.name) == "/workspace")
        let second = UserDefault<String?>(.standardTestPath)
        #expect(second.wrappedValue == "/workspace")
        path = nil
        #expect(second.wrappedValue == nil)
        #expect(UserDefaults.standard.object(forKey: StandardTestKey.name) == nil)
    }

    @Test
    func declarationAcceptsAnExplicitStore() throws {
        try withDefaults { defaults in
            let store = UserDefaultsStore(defaults: defaults)
            @UserDefault(.testWorkspacePath, store: store)
            var path: String?
            path = "/isolated"
            #expect(defaults.string(forKey: "path") == "/isolated")
            defaults.set("/updated", forKey: "path")
            #expect(path == "/updated")
        }
    }

    @Test
    func fallbackDoesNotWriteOrRegisterAnything() throws {
        try withDefaults { defaults in
            let store = UserDefaultsStore(defaults: defaults)
            let name = UUID().uuidString
            let key = UserDefaultsKey(name, default: 12)
            let wrapper = UserDefault(key, store: store)
            #expect(wrapper.wrappedValue == 12)
            let value = try store.read(key)
            #expect(value == 12)
            #expect(defaults.object(forKey: name) == nil)
            #expect(defaults.volatileDomain(forName: UserDefaults.registrationDomain)[name] == nil)
        }
    }

    @Test
    func accessorsShareTheKeyFallbackAndHaveNoStaleCache() throws {
        try withDefaults { defaults in
            let key = UserDefaultsKey("count", default: 12)
            let store = UserDefaultsStore(defaults: defaults)
            let first = UserDefault(key, store: store)
            let second = UserDefault(key, store: store)
            #expect(first.wrappedValue == second.wrappedValue)
            first.wrappedValue = 30
            #expect(second.wrappedValue == 30)
            defaults.set(40, forKey: "count")
            #expect(first.wrappedValue == 40)
            second.reset()
            #expect(first.wrappedValue == 12)
            #expect(second.wrappedValue == 12)
        }
    }

    @Test
    func anExplicitDefaultIsNotRemoved() throws {
        try withDefaults { defaults in
            let store = UserDefaultsStore(defaults: defaults)
            let key = UserDefaultsKey("count", default: 12)
            try store.set(12, for: key)
            #expect(defaults.object(forKey: "count") as? Int == 12)
            store.reset(key)
            #expect(defaults.object(forKey: "count") == nil)
        }
    }

    @Test
    func optionalNilRemovesStorageAndRevealsTheFallback() throws {
        try withDefaults { defaults in
            let store = UserDefaultsStore(defaults: defaults)
            let key = UserDefaultsKey<String?>("path", default: "/fallback")
            let wrapper = UserDefault(key, store: store)
            wrapper.wrappedValue = "/chosen"
            #expect(wrapper.wrappedValue == "/chosen")
            wrapper.wrappedValue = nil
            #expect(defaults.object(forKey: "path") == nil)
            #expect(wrapper.wrappedValue == "/fallback")
            let missing = try store.read(UserDefaultsKey<String?>("missing", default: nil))
            #expect(missing == nil)
        }
    }

    @Test
    func existingNativeStringsAndArraysKeepTheirRepresentation() throws {
        try withDefaults { defaults in
            defaults.set("/repo", forKey: "lastRepositoryPath")
            defaults.set(["/repo", "/other"], forKey: "recentRepositoryPaths")
            let store = UserDefaultsStore(defaults: defaults)
            let path = UserDefaultsKey<String?>("lastRepositoryPath", default: nil)
            let recent = UserDefaultsKey<[String]>("recentRepositoryPaths", default: [])
            #expect(try store.read(path) == "/repo")
            #expect(try store.read(recent) == ["/repo", "/other"])
            try store.set(["/new"], for: recent)
            #expect(defaults.stringArray(forKey: "recentRepositoryPaths") == ["/new"])
        }
    }

    @Test
    func nativeValuesRoundTrip() throws {
        try withDefaults { defaults in
            let store = UserDefaultsStore(defaults: defaults)
            try roundTrip(true, fallback: false, store: store)
            try roundTrip(42, fallback: 0, store: store)
            try roundTrip(1.25, fallback: 0.0, store: store)
            try roundTrip(Float(2.5), fallback: Float(0), store: store)
            try roundTrip("value", fallback: "", store: store)
            try roundTrip(Data([1, 2, 3]), fallback: Data(), store: store)
            try roundTrip(Date(timeIntervalSince1970: 1000), fallback: .distantPast, store: store)
            try roundTrip(["a": [1, 2]], fallback: [:], store: store)
        }
    }

    @Test
    func invalidNativeCollectionIsRejectedWithoutDroppingElements() throws {
        try withDefaults { defaults in
            let store = UserDefaultsStore(defaults: defaults)
            let key = UserDefaultsKey<[String?]>("values", default: [])
            try store.set(["old"], for: key)
            #expect(throws: UserDefaultsValueError.invalidPropertyList) {
                try store.set(["new", nil], for: key)
            }
            #expect(try store.read(key) == ["old"])
        }
    }

    @Test
    func customNativeRepresentationIsValidatedBeforeCallingFoundation() throws {
        try withDefaults { defaults in
            let store = UserDefaultsStore(defaults: defaults)
            let key = UserDefaultsKey("value", default: InvalidNativeValue())
            #expect(throws: UserDefaultsValueError.invalidPropertyList) {
                try store.set(InvalidNativeValue(), for: key)
            }
            #expect(defaults.object(forKey: "value") == nil)
        }
    }

    @Test
    func mixedStoredArrayIsNotSilentlyFiltered() throws {
        try withDefaults { defaults in
            defaults.set(["path", 1], forKey: "paths")
            let store = UserDefaultsStore(defaults: defaults)
            let key = UserDefaultsKey<[String]>("paths", default: [])
            #expect(throws: UserDefaultsValueError.self) { try store.read(key) }
            #expect(defaults.array(forKey: "paths")?.count == 2)
        }
    }

    @Test
    func codableUsesJSONDataAndPreservesNestedNulls() throws {
        try withDefaults { defaults in
            let store = UserDefaultsStore(defaults: defaults)
            let key = UserDefaultsKey<Options>.codable("options", default: .init(names: [], scale: 1))
            let value = Options(names: ["a", nil, "b"], scale: 2)
            try store.set(value, for: key)
            #expect(try store.read(key) == value)
            let data = try #require(defaults.data(forKey: "options"))
            #expect(try JSONDecoder().decode(Options.self, from: data) == value)
        }
    }

    @Test
    func codableOptionalNilRemovesTheKey() throws {
        try withDefaults { defaults in
            let store = UserDefaultsStore(defaults: defaults)
            let key = UserDefaultsKey<Options?>.codable("options", default: nil)
            try store.set(.init(names: ["a"], scale: 1), for: key)
            #expect(defaults.data(forKey: "options") != nil)
            try store.set(nil, for: key)
            #expect(defaults.object(forKey: "options") == nil)
            #expect(try store.read(key) == nil)
        }
    }

    @Test
    func corruptDataFallsBackAndReportsWithoutOverwriting() throws {
        try withDefaults { defaults in
            let failures = Mutex<[UserDefaultsFailure]>([])
            let store = UserDefaultsStore(defaults: defaults) { failure in
                failures.withLock { $0.append(failure) }
            }
            let key = UserDefaultsKey<Options>.codable("options", default: .init(names: [], scale: 1))
            let corrupt = Data("{broken".utf8)
            defaults.set(corrupt, forKey: "options")
            #expect(throws: DecodingError.self) { try store.read(key) }
            #expect(UserDefault(key, store: store).wrappedValue == key.defaultValue)
            #expect(defaults.data(forKey: "options") == corrupt)
            #expect(failures.withLock { $0.map(\.operation) } == [.read])
        }
    }

    @Test
    func failedEncodingPreservesThePreviousValueAndReportsPropertyWrites() throws {
        try withDefaults { defaults in
            let failures = Mutex<[UserDefaultsFailure]>([])
            let store = UserDefaultsStore(defaults: defaults) { failure in
                failures.withLock { $0.append(failure) }
            }
            let key = UserDefaultsKey<Options>.codable("options", default: .init(names: [], scale: 1))
            let wrapper = UserDefault(key, store: store)
            let previous = Options(names: ["saved"], scale: 2)
            try wrapper.set(previous)
            let invalid = Options(names: [], scale: .infinity)
            #expect(throws: EncodingError.self) { try wrapper.set(invalid) }
            wrapper.wrappedValue = invalid
            #expect(try store.read(key) == previous)
            #expect(failures.withLock { $0.map(\.operation) } == [.write])
        }
    }

    @Test
    func injectedSuitesDoNotShareWrites() throws {
        try withDefaults { firstDefaults in
            try withDefaults { secondDefaults in
                let first = WorkspaceModel(store: UserDefaultsStore(defaults: firstDefaults))
                let second = WorkspaceModel(store: UserDefaultsStore(defaults: secondDefaults))
                first.path = "/first"
                second.path = "/second"
                #expect(first.path == "/first")
                #expect(second.path == "/second")
                #expect(firstDefaults.string(forKey: "path") == "/first")
                #expect(secondDefaults.string(forKey: "path") == "/second")
            }
        }
    }

    @Test
    func concurrentExplicitUpdatesRetainEveryIncrement() throws {
        try withDefaults { defaults in
            let store = UserDefaultsStore(defaults: defaults)
            let key = UserDefaultsKey("count", default: 0)
            DispatchQueue.concurrentPerform(iterations: 500) { _ in
                do { try store.update(key) { $0 += 1 } }
                catch { Issue.record(error) }
            }
            let value = try store.read(key)
            #expect(value == 500)
        }
    }

    @Test
    func aThrowingMutationDoesNotCommit() throws {
        try withDefaults { defaults in
            let store = UserDefaultsStore(defaults: defaults)
            let key = UserDefaultsKey("count", default: 0)
            try store.set(4, for: key)
            #expect(throws: MutationFailure.stopped) {
                try store.update(key) { value in
                    value = 99
                    throw MutationFailure.stopped
                }
            }
            #expect(try store.read(key) == 4)
        }
    }

    @Test
    func failureCallbackRunsOutsideTheStoreLock() throws {
        try withDefaults { defaults in
            let slot = Mutex<UserDefaultsStore?>(nil)
            let key = UserDefaultsKey("count", default: 10)
            let store = UserDefaultsStore(defaults: defaults) { _ in
                let sameStore = slot.withLock { $0! }
                let finished = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    // A different thread must be able to acquire the same store's lock.
                    #expect((try? sameStore.read(UserDefaultsKey("other", default: 2))) == 2)
                    finished.signal()
                }
                #expect(finished.wait(timeout: .now() + 2) == .success)
            }
            slot.withLock { $0 = store }
            defer { slot.withLock { $0 = nil } }
            defaults.set("invalid", forKey: key.name)
            #expect(UserDefault(key, store: store).wrappedValue == 10)
        }
    }

    @MainActor @Test
    func observationBelongsToTheModelNotTheStorageAccessor() throws {
        try withDefaults { defaults in
            let model = ObservableWorkspaceModel(defaults: defaults)
            let changes = Mutex(0)
            withObservationTracking {
                _ = model.path
            } onChange: {
                changes.withLock { $0 += 1 }
            }
            model.path = "/visible"
            #expect(changes.withLock { $0 } == 1)
            #expect(defaults.string(forKey: "path") == "/visible")

            let externalChanges = Mutex(0)
            withObservationTracking {
                _ = model.path
            } onChange: {
                externalChanges.withLock { $0 += 1 }
            }
            defaults.set("/external", forKey: "path")
            #expect(externalChanges.withLock { $0 } == 0)
            #expect(model.path == "/external")
        }
    }
}

private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "UserDefaultsKitTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
}

private func roundTrip<Value: UserDefaultsValue & Equatable>(
    _ value: Value,
    fallback: Value,
    store: UserDefaultsStore,
) throws {
    let key = UserDefaultsKey(UUID().uuidString, default: fallback)
    try store.set(value, for: key)
    #expect(try store.read(key) == value)
}

private struct Options: Codable, Equatable, Sendable {
    var names: [String?]
    var scale: Double
}

private struct InvalidNativeValue: UserDefaultsValue {
    func encodeUserDefaultsValue() throws -> Any? {
        NSNull()
    }
}

private enum MutationFailure: Error { case stopped }

private final class WorkspaceModel {
    @UserDefault(.testWorkspacePath) var path: String?

    init(store: UserDefaultsStore = .standard) {
        _path = UserDefault(.testWorkspacePath, store: store)
    }
}

@MainActor @Observable
private final class ObservableWorkspaceModel {
    @ObservationIgnored @UserDefault private var storedPath: String?

    init(defaults: UserDefaults) {
        _storedPath = UserDefault(
            UserDefaultsKey<String?>("path", default: nil),
            store: UserDefaultsStore(defaults: defaults),
        )
    }

    var path: String? {
        get {
            access(keyPath: \.path)
            return storedPath
        }
        set {
            withMutation(keyPath: \.path) { storedPath = newValue }
        }
    }
}

private extension UserDefaultsKey {
    static var testWorkspacePath: UserDefaultsKey<String?> {
        .init("path", default: nil)
    }

    static var standardTestPath: UserDefaultsKey<String?> {
        .init(StandardTestKey.name, default: nil)
    }
}

private enum StandardTestKey {
    static let name = "UserDefaultsKitTests.\(UUID()).path"
}
