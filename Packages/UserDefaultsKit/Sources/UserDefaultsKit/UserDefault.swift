// Created by weixi on 2026/09/16.

/// A synchronous, non-caching accessor. Reads do not register Observation dependencies.
/// Writes can invalidate observed readers of the same storage. It does not provide a Binding.
@propertyWrapper
public struct UserDefault<Value: Sendable>: Sendable {
    private let key: UserDefaultsKey<Value>
    private let store: UserDefaultsStore

    public init(_ key: UserDefaultsKey<Value>, store: UserDefaultsStore = .standard) {
        self.key = key
        self.store = store
    }

    public var wrappedValue: Value {
        get { store.value(for: key) }
        nonmutating set { store.assign(newValue, for: key) }
    }

    public func set(_ value: Value) throws {
        try store.set(value, for: key)
    }

    public func reset() {
        store.reset(key)
    }

    /// Ordinary += and append remain separate getter/setter calls. Use this for a compound update.
    public func update(_ mutation: (inout Value) throws -> Void) throws {
        try store.update(key, mutation)
    }
}
