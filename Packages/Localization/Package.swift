// swift-tools-version: 6.2
//
//  Package.swift
//  Ravel
//
//  Created by weixi on 2026/09/12.
//  Copyright © 2026 Ravel. All rights reserved.
//

import PackageDescription

let package = Package(
    name: "Localization",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.library(name: "Localization", targets: ["Localization"])],
    targets: [
        .target(name: "Localization", resources: [.process("Resources")]),
        .testTarget(name: "LocalizationTests", dependencies: ["Localization"]),
    ],
)
