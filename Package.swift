// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "DyLibRuntimeLoader",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        // Must stay .dynamic: host and plugins have to share one copy of the
        // runtime (descriptor class metadata) for cross-boundary casts to work.
        .library(name: "DyLibPlugin", type: .dynamic, targets: ["DyLibPlugin"]),
        // Test fixtures are real dynamic libraries so integration tests can dlopen them.
        .library(name: "TestPluginFixtureInterface", type: .dynamic, targets: ["TestPluginFixtureInterface"]),
        .library(name: "TestPluginFixture", type: .dynamic, targets: ["TestPluginFixture"]),
        .executable(name: "dylib-plugin-verify", targets: ["dylib-plugin-verify"]),
        .plugin(name: "VerifyDyLibPlugin", targets: ["VerifyDyLibPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"602.0.0")
    ],
    targets: [
        .target(
            name: "DyLibPlugin",
            dependencies: ["DyLibPluginMacros"]),
        .macro(
            name: "DyLibPluginMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]),
        .target(
            name: "TestPluginFixtureInterface",
            dependencies: ["DyLibPlugin"]),
        .target(
            name: "TestPluginFixture",
            dependencies: ["TestPluginFixtureInterface", "DyLibPlugin"]),
        .executableTarget(
            name: "dylib-plugin-verify"),
        .plugin(
            name: "VerifyDyLibPlugin",
            capability: .command(
                intent: .custom(
                    verb: "verify-dylib-plugin",
                    description: "Verify that a built plugin binary exports the DyLibPlugin entry and marker symbols")),
            dependencies: ["dylib-plugin-verify"]),
        .testTarget(
            name: "DyLibPluginTests",
            dependencies: ["DyLibPlugin", "TestPluginFixtureInterface"]),
        .testTarget(
            name: "DyLibPluginMacrosTests",
            dependencies: [
                "DyLibPluginMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]),
    ]
)
