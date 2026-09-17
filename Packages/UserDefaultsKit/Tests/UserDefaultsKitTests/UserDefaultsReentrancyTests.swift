// Created by weixi on 2026/09/17.

import Dispatch
import Foundation
import Observation
import Synchronization
import Testing
import UserDefaultsKit

struct UserDefaultsReentrancyTests {
    @Test(arguments: [true, false], [ReentrantWriter.store, .foundation])
    func returningToTheOriginalValueInvalidatesAnIntermediateReader(
        existingObservationEntry: Bool, writer: ReentrantWriter,
    ) throws {
        try withDefaults { defaults in
            let store = UserDefaultsStore(defaults: defaults)
            let key = UserDefaultsKey("count", default: 0)
            try store.set(0, for: key)
            if existingObservationEntry { _ = store.observedValue(for: key) }
            let entered = Mutex(false)
            let observedValue = Mutex<Int?>(nil)
            let invalidations = Mutex(0)
            let token = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: defaults, queue: nil,
            ) { notification in
                guard (try? store.read(key)) == 1,
                      entered.withLock({ value in
                          if value { return false }
                          value = true
                          return true
                      }) else { return }
                let value = withObservationTracking {
                    store.observedValue(for: key)
                } onChange: {
                    invalidations.withLock { $0 += 1 }
                }
                observedValue.withLock { $0 = value }
                switch writer {
                case .store:
                    do { try store.set(0, for: key) }
                    catch { Issue.record(error) }
                case .foundation:
                    (notification.object as? UserDefaults)?.set(0, forKey: key.name)
                }
                // Delivery must wait until the surrounding set has released its lock.
                #expect(invalidations.withLock { $0 } == 0)
            }
            defer { NotificationCenter.default.removeObserver(token) }

            try store.set(1, for: key)

            #expect(observedValue.withLock { $0 } == 1)
            #expect(try store.read(key) == 0)
            #expect(invalidations.withLock { $0 } == 1)
        }
    }

    @Test(arguments: [UserDefaultsFailure.Operation.read, .write])
    func failuresFromNativeNotificationReentryWaitForTheOutermostUnlock(
        _ operation: UserDefaultsFailure.Operation,
    ) throws {
        try withDefaults { defaults in
            let trigger = UserDefaultsKey("trigger", default: 0)
            let invalidRead = UserDefaultsKey("invalidRead", default: 7)
            let invalidWrite = UserDefaultsKey<Double>.codable("invalidWrite", default: 1)
            defaults.set("corrupt", forKey: invalidRead.name)
            let slot = Mutex<UserDefaultsStore?>(nil)
            let inNativeCallback = Mutex(false)
            let failures = Mutex<[UserDefaultsFailure.Operation]>([])
            let store = UserDefaultsStore(defaults: defaults) { failure in
                failures.withLock { $0.append(failure.operation) }
                #expect(!inNativeCallback.withLock { $0 })
                guard let sameStore = slot.withLock({ $0 }) else {
                    Issue.record("Missing store in failure callback")
                    return
                }
                let finished = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    #expect((try? sameStore.read(trigger)) == 1)
                    finished.signal()
                }
                #expect(finished.wait(timeout: .now() + 2) == .success)
            }
            slot.withLock { $0 = store }
            defer { slot.withLock { $0 = nil } }
            try store.set(1, for: invalidWrite)
            let entered = Mutex(false)
            let token = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: defaults, queue: nil,
            ) { _ in
                guard (try? store.read(trigger)) == 1,
                      entered.withLock({ value in
                          if value { return false }
                          value = true
                          return true
                      }) else { return }
                inNativeCallback.withLock { $0 = true }
                defer { inNativeCallback.withLock { $0 = false } }
                switch operation {
                case .read:
                    #expect(UserDefault(invalidRead, store: store).wrappedValue == 7)
                case .write:
                    UserDefault(invalidWrite, store: store).wrappedValue = .infinity
                }
                #expect(failures.withLock { $0.isEmpty })
            }
            defer { NotificationCenter.default.removeObserver(token) }

            try store.set(1, for: trigger)

            #expect(entered.withLock { $0 })
            #expect(failures.withLock { $0 } == [operation])
            #expect(defaults.string(forKey: invalidRead.name) == "corrupt")
            #expect(try store.read(invalidWrite) == 1)
        }
    }

    enum ReentrantWriter: Sendable { case store, foundation }
}

private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "UserDefaultsReentrancyTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
}
