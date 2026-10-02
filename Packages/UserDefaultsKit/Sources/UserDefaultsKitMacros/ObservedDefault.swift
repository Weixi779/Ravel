//
//  ObservedDefault.swift
//  Ravel
//
//  Created by weixi on 2026/09/16.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import UserDefaultsKit

/// A persistent computed property whose reads participate in official Observation.
/// Place before @ObservationIgnored inside an @Observable type: this macro owns
/// the property's accessors. Reads use UserDefaultsStore.standard.
/// Defaults belong to the key; do not give the property an initializer.
@attached(accessor, names: named(get), named(set))
public macro ObservedDefault<Value: Sendable>(_ key: UserDefaultsKey<Value>) =
    #externalMacro(module: "UserDefaultsKitMacroPlugin", type: "ObservedDefaultMacro")

/// Uses a store owned by the enclosing model, for example `store: \Self.store`.
/// Keep that store stable for the model's lifetime; replacing it is not observed.
@attached(accessor, names: named(get), named(set))
public macro ObservedDefault<Owner, Value: Sendable>(
    _ key: UserDefaultsKey<Value>,
    store: KeyPath<Owner, UserDefaultsStore>,
) = #externalMacro(module: "UserDefaultsKitMacroPlugin", type: "ObservedDefaultMacro")
