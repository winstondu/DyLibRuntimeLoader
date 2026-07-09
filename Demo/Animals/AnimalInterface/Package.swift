// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AnimalInterface",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        // Interface modules must be dynamic so host and plugins share one
        // copy of the protocol metadata.
        .library(
            name: "AnimalInterface",
            type: .dynamic,
            targets: ["AnimalInterface"])
    ],
    dependencies: [
        .package(path: "../../..")
    ],
    targets: [
        .target(
            name: "AnimalInterface",
            dependencies: [
                .product(name: "DyLibPlugin", package: "DyLibRuntimeLoader")
            ])
    ]
)
