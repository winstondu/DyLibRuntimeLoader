// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AnimalToolkit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        // Plugin binaries must be dynamic so the host can dlopen them.
        .library(
            name: "AnimalToolkit",
            type: .dynamic,
            targets: ["AnimalToolkit"])
    ],
    dependencies: [
        .package(path: "../ToolkitInterface"),
        .package(path: "../../.."),
    ],
    targets: [
        .target(
            name: "AnimalToolkit",
            dependencies: [
                "ToolkitInterface",
                .product(name: "DyLibPlugin", package: "DyLibRuntimeLoader"),
            ])
    ]
)
