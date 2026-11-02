// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LoggerHost",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LoggerHost", targets: ["LoggerHost"])],
    dependencies: [
        .package(path: "../../../Examples/AnimalInterface"),
        .package(path: "../../.."),
    ],
    targets: [
        .executableTarget(name: "LoggerHost", dependencies: [
            .product(name: "AnimalInterface", package: "AnimalInterface"),
            .product(name: "DyLibRuntimeLoader", package: "DyLibRuntimeLoader"),
        ]),
    ],
    swiftLanguageModes: [.v5]
)
