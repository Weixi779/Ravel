// swift-tools-version: 6.2
//
//  Package.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

import PackageDescription

/// Generated UniFFI declarations. The application builds and links the native
/// archive via Tools/buildBackend; this package does not hide a network build.
let package = Package(
    name: "RavelBackend",
    platforms: [.macOS(.v15)],
    products: [.library(name: "RavelBackend", targets: ["RavelBackend"])],
    targets: [
        .systemLibrary(name: "RavelBackendFFI"),
        .target(name: "RavelBackend", dependencies: ["RavelBackendFFI"], linkerSettings: [
            .linkedFramework("Security"), .linkedFramework("SystemConfiguration"),
            .linkedLibrary("iconv"), .linkedLibrary("z"), .linkedLibrary("resolv"),
        ]),
    ],
)
