// swift-tools-version: 6.2
// Created by weixi on 2026/09/16.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "UserDefaultsKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "UserDefaultsKit", targets: ["UserDefaultsKit"]),
        .library(name: "UserDefaultsKitMacros", targets: ["UserDefaultsKitMacros"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
    ],
    targets: [
        .target(name: "UserDefaultsKit"),
        .macro(
            name: "UserDefaultsKitMacroPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "UserDefaultsKitMacros",
            dependencies: ["UserDefaultsKit", "UserDefaultsKitMacroPlugin"]
        ),
        .testTarget(name: "UserDefaultsKitTests", dependencies: ["UserDefaultsKit"]),
        .testTarget(
            name: "UserDefaultsKitMacrosTests",
            dependencies: ["UserDefaultsKit", "UserDefaultsKitMacros"]
        ),
        .testTarget(
            name: "UserDefaultsKitMacroPluginTests",
            dependencies: [
                "UserDefaultsKitMacroPlugin",
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
            ]
        ),
    ]
)
