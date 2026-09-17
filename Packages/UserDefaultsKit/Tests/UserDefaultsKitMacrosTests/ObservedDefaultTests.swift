// Created by weixi on 2026/09/16.

import Dispatch
import Foundation
import Observation
import Synchronization
import Testing
import UserDefaultsKit
import UserDefaultsKitMacros

@MainActor
struct ObservedDefaultTests {
    @Test
    func declarationCanUseTheStandardStore() {
        let model = StandardModel()
        defer { UserDefaultsStore.standard.reset(UserDefaultsKey<Int>.macroStandard) }
        #expect(model.count == 0)
        let notifications = changes { model.count }
        model.count = 4
        #expect(notifications.withLock { $0 } == 1)
        #expect(UserDefaults.standard.integer(forKey: MacroStandardKey.name) == 4)
    }

    @Test
    func missingValuesUseTheKeyDefaultWithoutPersistingIt() throws {
        try withDefaults { defaults, store in
            let model = Model(store: store)
            #expect(model.path == nil)
            #expect(model.count == 7)
            #expect(defaults.object(forKey: "count") == nil)
        }
    }

    @Test
    func twoModelsObserveTheSameKey() throws {
        try withDefaults { defaults, store in
            let first = Model(store: store)
            let second = Model(store: store)
            let firstChanges = changes { first.path }
            let secondChanges = changes { second.path }
            second.path = "/workspace"
            #expect(firstChanges.withLock { $0 } == 1)
            #expect(secondChanges.withLock { $0 } == 1)
            #expect(first.path == "/workspace")
            #expect(defaults.string(forKey: "workspace.path") == "/workspace")
        }
    }

    @Test(arguments: [Writer.wrapper, .store, .foundation])
    func otherWritePathsInvalidateTheMacro(_ writer: Writer) throws {
        try withDefaults { defaults, store in
            let model = Model(store: store)
            let notifications = changes { model.path }
            switch writer {
            case .wrapper:
                let accessor = UserDefault<String?>(.observedPath, store: store)
                accessor.wrappedValue = "/external"
            case .store:
                try store.set("/external", for: .observedPath)
            case .foundation:
                defaults.set("/external", forKey: "workspace.path")
            }
            #expect(notifications.withLock { $0 } == 1)
            #expect(model.path == "/external")
        }
    }

    @Test
    func unrelatedAndIdenticalWritesDoNotInvalidateReaders() throws {
        try withDefaults { defaults, store in
            let model = Model(store: store)
            model.path = "/same"
            let notifications = changes { model.path }
            model.count = 9
            model.path = "/same"
            defaults.set("/same", forKey: "workspace.path")
            #expect(notifications.withLock { $0 } == 0)
            model.path = "/different"
            #expect(notifications.withLock { $0 } == 1)
        }
    }

    @Test
    func plainWrapperReadsRemainUntracked() throws {
        try withDefaults { _, store in
            let model = Model(store: store)
            let observedChanges = changes { model.path }
            let accessor = UserDefault<String?>(.observedPath, store: store)
            let plainChanges = changes { accessor.wrappedValue }
            accessor.wrappedValue = "/new"
            #expect(observedChanges.withLock { $0 } == 1)
            #expect(plainChanges.withLock { $0 } == 0)
        }
    }

    @Test
    func resetAndCompoundUpdateNotifyReaders() throws {
        try withDefaults { _, store in
            let model = Model(store: store)
            model.count = 12
            let resetChanges = changes { model.count }
            store.reset(UserDefaultsKey<Int>.observedCount)
            #expect(model.count == 7)
            #expect(resetChanges.withLock { $0 } == 1)
            let updateChanges = changes { model.count }
            try store.update(UserDefaultsKey<Int>.observedCount) { $0 += 3 }
            #expect(model.count == 10)
            #expect(updateChanges.withLock { $0 } == 1)
        }
    }

    @Test
    func optionalNilRemovesTheValueAndNotifies() throws {
        try withDefaults { defaults, store in
            let model = Model(store: store)
            model.path = "/workspace"
            let notifications = changes { model.path }
            model.path = nil
            #expect(model.path == nil)
            #expect(defaults.object(forKey: "workspace.path") == nil)
            #expect(notifications.withLock { $0 } == 1)
        }
    }

    @Test
    func codableChangesNotifyButFailedEncodingDoesNot() throws {
        try withDefaults { _, store in
            let model = Model(store: store)
            let notifications = changes { model.options }
            model.options = Options(scale: .infinity)
            #expect(model.options == Options(scale: 1))
            #expect(notifications.withLock { $0 } == 0)
            model.options = Options(scale: 2)
            #expect(model.options == Options(scale: 2))
            #expect(notifications.withLock { $0 } == 1)
        }
    }

    @Test
    func separateSuitesDoNotShareObservation() throws {
        try withDefaults { _, firstStore in
            try withDefaults { _, secondStore in
                let first = Model(store: firstStore)
                let second = Model(store: secondStore)
                let notifications = changes { first.path }
                second.path = "/second"
                #expect(first.path == nil)
                #expect(notifications.withLock { $0 } == 0)
                first.path = "/first"
                #expect(notifications.withLock { $0 } == 1)
            }
        }
    }

    @Test
    func callbacksCanReadTheStoreFromAnotherThread() throws {
        try withDefaults { _, store in
            let model = Model(store: store)
            let finished = DispatchSemaphore(value: 0)
            withObservationTracking { _ = model.path } onChange: {
                DispatchQueue.global().async {
                    #expect((try? store.read(UserDefaultsKey<String?>.observedPath)) == "/new")
                    finished.signal()
                }
                #expect(finished.wait(timeout: .now() + 2) == .success)
            }
            model.path = "/new"
        }
    }

    @Test
    func backgroundWritesNotifyWithoutMutatingTheMainActorModel() async throws {
        let suite = "ObservedDefaultTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsStore(defaults: defaults)
        let model = Model(store: store)
        let notifications = changes { model.path }
        try await Task.detached {
            try store.set("/background", for: UserDefaultsKey<String?>.observedPath)
        }.value
        #expect(model.path == "/background")
        #expect(notifications.withLock { $0 } == 1)
    }

    @Test
    func concurrentObservationAndCompoundUpdatesKeepEveryWrite() throws {
        try withDefaults { _, store in
            let key = UserDefaultsKey("concurrent", default: 0)
            DispatchQueue.concurrentPerform(iterations: 300) { iteration in
                if iteration.isMultiple(of: 3) {
                    _ = store.observedValue(for: key)
                } else {
                    do { try store.update(key) { $0 += 1 } }
                    catch { Issue.record(error) }
                }
            }
            let result = try store.read(key)
            #expect(result == 200)
        }
    }

    @Test
    func observationDoesNotKeepTheStoreAlive() throws {
        let suite = "ObservedDefaultTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        weak var releasedStore: UserDefaultsStore?
        let notifications = Mutex(0)
        autoreleasepool {
            let store = UserDefaultsStore(defaults: defaults)
            releasedStore = store
            withObservationTracking {
                _ = store.observedValue(for: UserDefaultsKey<String?>.observedPath)
            } onChange: {
                notifications.withLock { $0 += 1 }
            }
        }
        #expect(releasedStore == nil)
        defaults.set("/after-release", forKey: "workspace.path")
        #expect(notifications.withLock { $0 } == 0)
    }

    enum Writer: Sendable { case wrapper, store, foundation }
}

@MainActor
private func changes(_ read: () -> some Any) -> ChangeCount {
    let result = ChangeCount()
    withObservationTracking { _ = read() } onChange: {
        result.withLock { $0 += 1 }
    }
    return result
}

private final class ChangeCount: Sendable {
    private let count = Mutex(0)

    func withLock<Result: Sendable>(_ body: (inout Int) -> Result) -> Result {
        count.withLock { body(&$0) }
    }
}

@MainActor
private func withDefaults(_ body: (UserDefaults, UserDefaultsStore) throws -> Void) throws {
    let suite = "ObservedDefaultTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults, UserDefaultsStore(defaults: defaults))
}

@MainActor @Observable
private final class Model {
    private let store: UserDefaultsStore

    @ObservedDefault(.observedPath, store: \Self.store) @ObservationIgnored var path: String?

    @ObservedDefault(.observedCount, store: \Self.store) @ObservationIgnored var count: Int

    @ObservedDefault(.observedOptions, store: \Self.store) @ObservationIgnored var options: Options

    init(store: UserDefaultsStore) {
        self.store = store
    }
}

private struct Options: Codable, Equatable, Sendable {
    var scale: Double
}

@MainActor @Observable
private final class StandardModel {
    @ObservedDefault(.macroStandard) @ObservationIgnored var count: Int
}

private enum MacroStandardKey {
    static let name = "ObservedDefaultTests.\(UUID()).standard"
}

private extension UserDefaultsKey {
    static var macroStandard: UserDefaultsKey<Int> {
        .init(MacroStandardKey.name, default: 0)
    }

    static var observedPath: UserDefaultsKey<String?> {
        .init("workspace.path", default: nil)
    }

    static var observedCount: UserDefaultsKey<Int> {
        .init("count", default: 7)
    }

    static var observedOptions: UserDefaultsKey<Options> {
        .codable("options", default: .init(scale: 1))
    }
}
