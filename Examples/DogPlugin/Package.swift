// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DogPlugin",
    platforms: [.macOS(.v10_15)],
    products: [.library(name: "DogPlugin", type: .dynamic, targets: ["DogPlugin"])],
    dependencies: [
        .package(path: "../AnimalInterface"),
        .package(path: "../TrickInterface"),
        .package(path: "../.."),
    ],
    targets: [
        .target(name: "DogPlugin", dependencies: [
            .product(name: "AnimalInterface", package: "AnimalInterface"),
            .product(name: "TrickInterface", package: "TrickInterface"),
            .product(name: "Dynasty", package: "Dynasty"),
        ]),
    ],
    swiftLanguageModes: [.v5]
)
