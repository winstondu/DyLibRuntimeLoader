// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LoggedDogPlugin",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LoggedDogPlugin", type: .dynamic, targets: ["LoggedDogPlugin"])],
    dependencies: [
        .package(path: "../../../Examples/AnimalInterface"),
        .package(path: "../../../Examples/TrickInterface"),
        .package(path: "../../.."),
    ],
    targets: [
        .target(name: "LoggedDogPlugin", dependencies: [
            .product(name: "AnimalInterface", package: "AnimalInterface"),
            .product(name: "TrickInterface", package: "TrickInterface"),
            .product(name: "Dynasty", package: "Dynasty"),
        ]),
    ],
    swiftLanguageModes: [.v5]
)
