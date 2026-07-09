// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ToolkitInterface",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        // Interface modules must be dynamic so host and plugins share one
        // copy of the protocol metadata.
        .library(
            name: "ToolkitInterface",
            type: .dynamic,
            targets: ["ToolkitInterface"])
    ],
    dependencies: [
        .package(path: "../../..")
    ],
    targets: [
        .target(
            name: "ToolkitInterface",
            dependencies: [
                .product(name: "DyLibPlugin", package: "DyLibRuntimeLoader")
            ])
    ]
)
