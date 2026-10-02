//
//  UserDefaultsValueTypeTests.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
import Observation
import Synchronization
import Testing
import UserDefaultsKit

struct UserDefaultsValueTypeTests {
    @Test
    func numericStringsKeepTheirTypeAndLeadingZeros() throws {
        try withDefaults { _, store in
            let string = UserDefaultsKey("string", default: "")
            let integer = UserDefaultsKey("integer", default: 0)
            try store.set("01", for: string)
            try store.set(1, for: integer)

            #expect(try store.read(string) == "01")
            #expect(try store.read(integer) == 1)
            #expect(throws: UserDefaultsValueError.self) {
                try store.read(UserDefaultsKey("string", default: 0))
            }
            #expect(throws: UserDefaultsValueError.self) {
                try store.read(UserDefaultsKey("integer", default: ""))
            }
        }
    }

    @Test(arguments: [StoredNumber.boolean, .integer, .floatingPoint])
    func numericKeysRequireTheMatchingStorageCategory(_ stored: StoredNumber) throws {
        try withDefaults { _, store in
            let boolean = UserDefaultsKey("value", default: false)
            let integer = UserDefaultsKey("value", default: 0)
            let double = UserDefaultsKey("value", default: Double(0))
            let float = UserDefaultsKey("value", default: Float(0))
            switch stored {
            case .boolean:
                try store.set(true, for: boolean)
                #expect(try store.read(boolean))
                #expect(throws: UserDefaultsValueError.self) { try store.read(integer) }
                #expect(throws: UserDefaultsValueError.self) { try store.read(double) }
                #expect(throws: UserDefaultsValueError.self) { try store.read(float) }
            case .integer:
                try store.set(1, for: integer)
                #expect(try store.read(integer) == 1)
                #expect(throws: UserDefaultsValueError.self) { try store.read(boolean) }
                #expect(throws: UserDefaultsValueError.self) { try store.read(double) }
                #expect(throws: UserDefaultsValueError.self) { try store.read(float) }
            case .floatingPoint:
                try store.set(1, for: double)
                #expect(try store.read(double) == 1)
                #expect(try store.read(float) == 1)
                #expect(throws: UserDefaultsValueError.self) { try store.read(boolean) }
                #expect(throws: UserDefaultsValueError.self) { try store.read(integer) }
            }
        }
    }

    @Test
    func containersApplyTheSameTypeRulesToTheirValues() throws {
        try withDefaults { defaults, store in
            defaults.set(true, forKey: "optional")
            defaults.set([true], forKey: "array")
            defaults.set(["nested": [true]], forKey: "dictionary")
            #expect(throws: UserDefaultsValueError.self) {
                try store.read(UserDefaultsKey<Int?>("optional", default: nil))
            }
            #expect(throws: UserDefaultsValueError.self) {
                try store.read(UserDefaultsKey<[Int]>("array", default: []))
            }
            #expect(throws: UserDefaultsValueError.self) {
                try store.read(UserDefaultsKey<[String: [Int]]>("dictionary", default: [:]))
            }
        }
    }

    @Test(arguments: [ValueShape.boolean, .integer, .array, .dictionary])
    func numericallyEqualTypeChangesStillInvalidateReaders(_ shape: ValueShape) throws {
        try withDefaults { defaults, store in
            switch shape {
            case .boolean:
                try checkTypeChange(valid: true, invalid: 1, fallback: false, defaults: defaults, store: store)
            case .integer:
                try checkTypeChange(valid: 1, invalid: Double(1), fallback: 0, defaults: defaults, store: store)
            case .array:
                try checkTypeChange(valid: [true], invalid: [1], fallback: [], defaults: defaults, store: store)
            case .dictionary:
                try checkTypeChange(
                    valid: ["nested": [true]],
                    invalid: ["nested": [1]],
                    fallback: [:],
                    defaults: defaults,
                    store: store,
                )
            }
        }
    }

    enum StoredNumber: Sendable { case boolean, integer, floatingPoint }
    enum ValueShape: Sendable { case boolean, integer, array, dictionary }
}

private func checkTypeChange<Value: UserDefaultsValue & Equatable>(
    valid: Value,
    invalid: Any,
    fallback: Value,
    defaults: UserDefaults,
    store: UserDefaultsStore,
) throws {
    let key = UserDefaultsKey(UUID().uuidString, default: fallback)
    // Exercise an actual representation change between search domains. UserDefaults
    // can elide a same-domain set when NSNumber/collection equality considers it equal.
    defaults.register(defaults: [key.name: valid])
    let changes = Mutex(0)
    withObservationTracking {
        #expect(store.observedValue(for: key) == valid)
    } onChange: {
        changes.withLock { $0 += 1 }
    }
    defaults.set(invalid, forKey: key.name)
    #expect(changes.withLock { $0 } == 1)
    #expect(store.observedValue(for: key) == fallback)
    #expect(throws: UserDefaultsValueError.self) { try store.read(key) }
    #expect(defaults.object(forKey: key.name) != nil)

    withObservationTracking {
        _ = store.observedValue(for: key)
    } onChange: {
        changes.withLock { $0 += 1 }
    }
    store.reset(key)
    #expect(changes.withLock { $0 } == 2)
    #expect(store.observedValue(for: key) == valid)
}

private func withDefaults(_ body: (UserDefaults, UserDefaultsStore) throws -> Void) throws {
    let suite = "UserDefaultsValueTypeTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults, UserDefaultsStore(defaults: defaults, onFailure: { _ in }))
}
