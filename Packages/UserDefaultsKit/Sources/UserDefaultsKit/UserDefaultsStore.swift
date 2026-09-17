// Created by weixi on 2026/09/16.

import Foundation
import OSLog
import Synchronization

/// A failure from a nonthrowing property access. Explicit read/set/update calls throw instead.
public struct UserDefaultsFailure: Sendable {
    public enum Operation: String, Sendable { case read, write }

    public let operation: Operation
    public let key: String
    public let error: any Error
}

/// Synchronous storage. Share one instance to coordinate compound updates.
/// This does not coordinate direct UserDefaults calls, other stores, or other processes.
public final class UserDefaultsStore: Sendable {
    /// Default accessors share one store and its update coordination. Inject a separate
    /// store for tests or previews instead of replacing this global default.
    public static let standard = UserDefaultsStore(defaults: .standard)

    private static let logger = Logger(subsystem: "UserDefaultsKit", category: "Storage")
    private let reference: DefaultsReference
    private let observations: UserDefaultsObservations
    // Foundation observers may synchronously read this store while a write is in progress.
    private let lock = NSRecursiveLock()
    private struct OperationState {
        // Counts recursion on the thread holding `lock`, not waiting/concurrent callers.
        var depth = 0
        var failures: [UserDefaultsFailure] = []
    }
    // The recursive lock serializes operations; this short-held mutex keeps their
    // bookkeeping compiler-checked Sendable. No storage or client code runs under it.
    private let operation = Mutex(OperationState())
    private let onFailure: @Sendable (UserDefaultsFailure) -> Void

    public init(
        defaults: UserDefaults,
        onFailure: (@Sendable (UserDefaultsFailure) -> Void)? = nil
    ) {
        let reference = DefaultsReference(defaults)
        self.reference = reference
        observations = UserDefaultsObservations(reference: reference)
        self.onFailure = onFailure ?? Self.logFailure
    }

    /// Missing data uses the key's fallback; invalid existing data throws and remains intact.
    public func read<Value>(_ key: UserDefaultsKey<Value>) throws -> Value {
        try withAccess { try readUnlocked(key) }
    }

    /// Reads with the same fallback/error policy as UserDefault and records an Observation
    /// dependency on this store and key. Used by @ObservedDefault; ordinary reads stay untracked.
    public func observedValue<Value>(for key: UserDefaultsKey<Value>) -> Value {
        withAccess {
            observations.access(key.name)
            return valueUnlocked(for: key)
        }
    }

    /// Encodes before changing storage. A failed encoding preserves the previous stored value.
    public func set<Value>(_ value: Value, for key: UserDefaultsKey<Value>) throws {
        try withAccess { try writeUnlocked(value, for: key) }
    }

    public func reset<Value>(_ key: UserDefaultsKey<Value>) {
        withAccess { reference.defaults.removeObject(forKey: key.name) }
    }

    /// Holds this store's lock across read, mutation, encoding, and write.
    /// Keep the closure short: mutate the supplied value without accessing the store or doing IO.
    /// Throwing skips the write; it cannot undo external side effects from the closure.
    public func update<Value>(
        _ key: UserDefaultsKey<Value>,
        _ mutation: (inout Value) throws -> Void
    ) throws {
        try withAccess {
            var value = try readUnlocked(key)
            try mutation(&value)
            try writeUnlocked(value, for: key)
        }
    }

    private func withAccess<Result>(_ body: () throws -> Result) rethrows -> Result {
        // Defer observation delivery before acquiring the storage lock, and resume it
        // only after unlocking. Unlike operation.depth, this includes concurrent callers.
        observations.beginAccess()
        lock.lock()
        operation.withLock { $0.depth += 1 }
        defer {
            let failures = operation.withLock { state in
                state.depth -= 1
                guard state.depth == 0 else { return [UserDefaultsFailure]() }
                let failures = state.failures
                state.failures.removeAll(keepingCapacity: true)
                return failures
            }
            lock.unlock()
            observations.endAccess()
            // A nested read/write only queues failures. The outermost operation takes
            // and delivers them on its calling thread after releasing every lock level.
            failures.forEach(onFailure)
        }
        return try body()
    }

    func value<Value>(for key: UserDefaultsKey<Value>) -> Value {
        withAccess { valueUnlocked(for: key) }
    }

    func assign<Value>(_ value: Value, for key: UserDefaultsKey<Value>) {
        withAccess {
            do {
                try writeUnlocked(value, for: key)
            } catch {
                operation.withLock {
                    $0.failures.append(.init(operation: .write, key: key.name, error: error))
                }
            }
        }
    }

    private func valueUnlocked<Value>(for key: UserDefaultsKey<Value>) -> Value {
        do {
            return try readUnlocked(key)
        } catch {
            operation.withLock {
                $0.failures.append(.init(operation: .read, key: key.name, error: error))
            }
            return key.defaultValue
        }
    }

    private func readUnlocked<Value>(_ key: UserDefaultsKey<Value>) throws -> Value {
        guard let object = reference.defaults.object(forKey: key.name) else { return key.defaultValue }
        return try key.decode(object)
    }

    private func writeUnlocked<Value>(_ value: Value, for key: UserDefaultsKey<Value>) throws {
        guard let object = try key.encode(value) else {
            reference.defaults.removeObject(forKey: key.name)
            return
        }
        guard PropertyListSerialization.propertyList(object, isValidFor: .binary) else {
            throw UserDefaultsValueError.invalidPropertyList
        }
        reference.defaults.set(object, forKey: key.name)
    }

    private static func logFailure(_ failure: UserDefaultsFailure) {
        logger.error("Preferences \(failure.operation.rawValue, privacy: .public) failed key=\(failure.key, privacy: .public) errorType=\(String(reflecting: type(of: failure.error)), privacy: .public)")
    }
}

// Foundation documents UserDefaults as thread-safe, but does not declare it Sendable.
// Only this immutable reference bridge needs an unchecked conformance. Store state and
// closures remain compiler-checked; the store's lock additionally coordinates update().
final class DefaultsReference: @unchecked Sendable {
    let defaults: UserDefaults
    init(_ defaults: UserDefaults) { self.defaults = defaults }
}
