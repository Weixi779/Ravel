//
//  UserDefaultsValue.swift
//  Ravel
//
//  Created by weixi on 2026/09/16.
//  Copyright © 2026 Ravel. All rights reserved.
//

import CoreFoundation
import Foundation

/// A value with a native UserDefaults representation. Use a Codable key for models.
public protocol UserDefaultsValue: Sendable {
    static func decodeUserDefaultsValue(_ object: Any) throws -> Self
    /// Returning nil removes the stored value. Collection elements must not return nil.
    func encodeUserDefaultsValue() throws -> Any?
}

public enum UserDefaultsValueError: Error, Equatable {
    case typeMismatch(expected: String)
    case invalidPropertyList
}

public extension UserDefaultsValue {
    static func decodeUserDefaultsValue(_ object: Any) throws -> Self {
        guard let value = object as? Self else {
            throw UserDefaultsValueError.typeMismatch(expected: String(reflecting: Self.self))
        }
        return value
    }

    func encodeUserDefaultsValue() throws -> Any? {
        self
    }
}

extension String: UserDefaultsValue {}
extension Bool: UserDefaultsValue {
    public static func decodeUserDefaultsValue(_ object: Any) throws -> Self {
        try decodeNumber(object, kind: .boolean)
    }
}

extension Int: UserDefaultsValue {
    public static func decodeUserDefaultsValue(_ object: Any) throws -> Self {
        try decodeNumber(object, kind: .integer)
    }
}

extension Double: UserDefaultsValue {
    public static func decodeUserDefaultsValue(_ object: Any) throws -> Self {
        try decodeNumber(object, kind: .floatingPoint)
    }
}

extension Float: UserDefaultsValue {
    public static func decodeUserDefaultsValue(_ object: Any) throws -> Self {
        try decodeNumber(object, kind: .floatingPoint)
    }
}

extension Data: UserDefaultsValue {}
extension Date: UserDefaultsValue {}

/// Match the native storage category before unboxing NSNumber. Swift's conditional
/// cast alone also accepts cross-category values such as true -> Int and 1.0 -> Int.
/// Float and Double share the floating-point category; the cast still checks precision.
enum UserDefaultsNumberKind {
    case boolean, integer, floatingPoint

    init(_ number: NSNumber) {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            self = .boolean
        } else {
            switch String(cString: number.objCType) {
            case "f", "d": self = .floatingPoint
            default: self = .integer
            }
        }
    }
}

private func decodeNumber<Value>(_ object: Any, kind: UserDefaultsNumberKind) throws -> Value {
    guard let number = object as? NSNumber,
          UserDefaultsNumberKind(number) == kind,
          let value = object as? Value
    else {
        throw UserDefaultsValueError.typeMismatch(expected: String(reflecting: Value.self))
    }
    return value
}

extension Optional: UserDefaultsValue where Wrapped: UserDefaultsValue {
    public static func decodeUserDefaultsValue(_ object: Any) throws -> Self {
        try .some(Wrapped.decodeUserDefaultsValue(object))
    }

    public func encodeUserDefaultsValue() throws -> Any? {
        switch self {
        case .none: nil
        case let .some(value): try value.encodeUserDefaultsValue()
        }
    }
}

extension Array: UserDefaultsValue where Element: UserDefaultsValue {
    public static func decodeUserDefaultsValue(_ object: Any) throws -> Self {
        guard let values = object as? [Any] else {
            throw UserDefaultsValueError.typeMismatch(expected: String(reflecting: Self.self))
        }
        return try values.map(Element.decodeUserDefaultsValue)
    }

    public func encodeUserDefaultsValue() throws -> Any? {
        try map { element in
            guard let value = try element.encodeUserDefaultsValue() else {
                throw UserDefaultsValueError.invalidPropertyList
            }
            return value
        }
    }
}

extension Dictionary: UserDefaultsValue where Key == String, Value: UserDefaultsValue {
    public static func decodeUserDefaultsValue(_ object: Any) throws -> Self {
        guard let values = object as? [String: Any] else {
            throw UserDefaultsValueError.typeMismatch(expected: String(reflecting: Self.self))
        }
        return try values.mapValues(Value.decodeUserDefaultsValue)
    }

    public func encodeUserDefaultsValue() throws -> Any? {
        try mapValues { element in
            guard let value = try element.encodeUserDefaultsValue() else {
                throw UserDefaultsValueError.invalidPropertyList
            }
            return value
        }
    }
}
