// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CatPlugin",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        // Plugin binaries must be dynamic so the host can dlopen them.
        .library(
            name: "CatPlugin",
            type: .dynamic,
            targets: ["CatPlugin"])
    ],
    dependencies: [
        .package(path: "../AnimalInterface"),
        .package(path: "../../.."),
    ],
    targets: [
        .target(
            name: "CatPlugin",
            dependencies: [
                "AnimalInterface",
                .product(name: "DyLibPlugin", package: "DyLibRuntimeLoader"),
            ])
    ]
)
