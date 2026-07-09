// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DogPlugin",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        // Plugin binaries must be dynamic so the host can dlopen them.
        .library(
            name: "DogPlugin",
            type: .dynamic,
            targets: ["DogPlugin"])
    ],
    dependencies: [
        .package(path: "../AnimalInterface"),
        .package(path: "../ToolkitInterface"),
        .package(path: "../../.."),
    ],
    targets: [
        .target(
            name: "DogPlugin",
            dependencies: [
                "AnimalInterface",
                "ToolkitInterface",
                .product(name: "DyLibPlugin", package: "DyLibRuntimeLoader"),
            ])
    ]
)
