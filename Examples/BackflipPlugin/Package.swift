// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BackflipPlugin",
    platforms: [.macOS(.v10_15)],
    products: [.library(name: "BackflipPlugin", type: .dynamic, targets: ["BackflipPlugin"])],
    dependencies: [
        .package(path: "../TrickInterface"),
        .package(path: "../.."),
    ],
    targets: [
        .target(name: "BackflipPlugin", dependencies: [
            .product(name: "TrickInterface", package: "TrickInterface"),
            .product(name: "Dynasty", package: "DyLibRuntimeLoader"),
        ]),
    ],
    swiftLanguageModes: [.v5]
)
