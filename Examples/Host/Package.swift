// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Host",
    platforms: [.macOS(.v10_15)],
    products: [.executable(name: "Host", targets: ["Host"])],
    dependencies: [
        .package(path: "../AnimalInterface"),
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(name: "Host", dependencies: [
            .product(name: "AnimalInterface", package: "AnimalInterface"),
            .product(name: "Dynasty", package: "Dynasty"),
        ]),
    ],
    swiftLanguageModes: [.v5]
)
