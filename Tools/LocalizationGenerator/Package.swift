// swift-tools-version: 6.2
// Created by weixi on 2026/09/12.

import PackageDescription

let package = Package(
    name: "LocalizationGenerator",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "generate-localization", targets: ["GenerateLocalization"])],
    targets: [
        .target(name: "CatalogGenerator"),
        .executableTarget(name: "GenerateLocalization", dependencies: ["CatalogGenerator"]),
        .testTarget(name: "CatalogGeneratorTests", dependencies: ["CatalogGenerator"]),
    ]
)
