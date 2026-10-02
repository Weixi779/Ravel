// swift-tools-version: 6.2
//
//  Package.swift
//  Ravel
//
//  Created by weixi on 2026/09/12.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import PackageDescription

let package = Package(
    name: "Logger",
    platforms: [.macOS(.v15)],
    products: [.library(name: "Logger", targets: ["Logger"])],
    targets: [
        .target(name: "Logger"),
    ],
)
