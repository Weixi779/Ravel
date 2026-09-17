// Created by weixi on 2026/09/16.

import Foundation

/// Declare each preference once, including its fallback and persistent representation.
/// Keys do not bind a suite, register defaults, or write their fallback to storage.
public struct UserDefaultsKey<Value: Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value
    let decode: @Sendable (Any) throws -> Value
    let encode: @Sendable (Value) throws -> Any?

    public init(_ name: String, default defaultValue: Value) where Value: UserDefaultsValue {
        self.name = name
        self.defaultValue = defaultValue
        self.decode = { try Value.decodeUserDefaultsValue($0) }
        self.encode = { try $0.encodeUserDefaultsValue() }
    }

    /// Stores JSON Data. An outer Optional.none removes the key instead of writing JSON null.
    public static func codable(_ name: String, default defaultValue: Value) -> Self where Value: Codable {
        Self(
            name: name,
            defaultValue: defaultValue,
            decode: { object in
                guard let data = object as? Data else {
                    throw UserDefaultsValueError.typeMismatch(expected: "Foundation.Data")
                }
                return try JSONDecoder().decode(Value.self, from: data)
            },
            encode: { value in
                if let optional = value as? any OptionalValue, optional.isNil { return nil }
                return try JSONEncoder().encode(value)
            }
        )
    }

    private init(
        name: String,
        defaultValue: Value,
        decode: @escaping @Sendable (Any) throws -> Value,
        encode: @escaping @Sendable (Value) throws -> Any?
    ) {
        self.name = name
        self.defaultValue = defaultValue
        self.decode = decode
        self.encode = encode
    }
}

private protocol OptionalValue {
    var isNil: Bool { get }
}

extension Optional: OptionalValue {
    fileprivate var isNil: Bool {
        if case .none = self { return true }
        return false
    }
}
