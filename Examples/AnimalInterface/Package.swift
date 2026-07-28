// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnimalInterface",
    platforms: [.macOS(.v10_15)],
    products: [.library(name: "AnimalInterface", type: .dynamic, targets: ["AnimalInterface"])],
    dependencies: [.package(path: "../..")],
    targets: [
        .target(
            name: "AnimalInterface",
            dependencies: [.product(name: "DyLibRuntimeLoader", package: "DyLibRuntimeLoader")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
