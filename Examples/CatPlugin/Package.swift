// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CatPlugin",
    platforms: [.macOS(.v10_15)],
    products: [.library(name: "CatPlugin", type: .dynamic, targets: ["CatPlugin"])],
    dependencies: [
        .package(path: "../AnimalInterface"),
        .package(path: "../.."),
    ],
    targets: [
        .target(name: "CatPlugin", dependencies: [
            .product(name: "AnimalInterface", package: "AnimalInterface"),
            .product(name: "Dynasty", package: "DyLibRuntimeLoader"),
        ]),
    ],
    swiftLanguageModes: [.v5]
)
