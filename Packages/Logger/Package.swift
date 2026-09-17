// swift-tools-version: 6.2
// Created by weixi on 2026/09/12.

import PackageDescription

let package = Package(
    name: "Logger",
    platforms: [.macOS(.v15)],
    products: [.library(name: "Logger", targets: ["Logger"])],
    targets: [
        .target(name: "Logger"),
    ],
)
