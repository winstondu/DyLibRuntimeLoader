// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DemoLogging",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(
            name: "DemoLogging",
            type: .dynamic,
            targets: ["DemoLogging"]),
    ],
    dependencies: [
        .package(path: "../../.."),
    ],
    targets: [
        .target(
            name: "DemoLogging",
            dependencies: [
                .product(name: "DyLibRuntimeLoader", package: "DyLibRuntimeLoader"),
            ]),
    ],
    swiftLanguageModes: [.v5]
)
