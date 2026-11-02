// swift-tools-version: 6.0

import CompilerPluginSupport
import Foundation
import PackageDescription

let shippingSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0"),
]

var targets: [Target] = [
    .macro(
        name: "DynastyMacros",
        dependencies: [
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        ],
        swiftSettings: shippingSettings
    ),
    .target(
        name: "Dynasty",
        dependencies: ["DynastyMacros"],
        swiftSettings: shippingSettings
    ),
]

if ProcessInfo.processInfo.environment["DYLIB_DEV"] == "1" {
    #if arch(arm64)
    let architecture = "arm64"
    #elseif arch(x86_64)
    let architecture = "x86_64"
    #else
    #error("DYLIB_DEV tests support arm64 and x86_64 macOS hosts")
    #endif

    let testSettings: [SwiftSetting] = [
        .enableExperimentalFeature("StrictConcurrency"),
    ]
    let testLinkerSettings: [LinkerSetting] = [
        .unsafeFlags([
            "-target", "\(architecture)-apple-macosx14.0",
            "-L", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
            "-Xlinker", "-rpath",
            "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
        ]),
    ]

    dependencies.append(.package(
        url: "https://github.com/swiftlang/swift-testing.git",
        revision: "48d727cc1cf4eda667c858c501495f1018f69d21"
    ))
    targets += [
        .testTarget(
            name: "DynastyMacroTests",
            dependencies: [
                "DynastyMacros",
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: testSettings
        ),
        .testTarget(
            name: "DynastyTests",
            dependencies: [
                "Dynasty",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: testSettings,
            linkerSettings: testLinkerSettings
        ),
    ]
}

let package = Package(
    name: "Dynasty",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "Dynasty",
            type: .dynamic,
            targets: ["Dynasty"]
        ),
    ],
    dependencies: dependencies,
    targets: targets,
    swiftLanguageModes: [.v5]
)
