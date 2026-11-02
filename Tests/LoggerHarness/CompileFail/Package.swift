// swift-tools-version: 6.0
import PackageDescription

// Must FAIL to build: `logger:` names a type that does not conform to DyLibLoadLogger.
let package = Package(
    name: "CompileFail",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../../Examples/AnimalInterface"),
        .package(path: "../../.."),
    ],
    targets: [
        .target(name: "CompileFail", dependencies: [
            .product(name: "AnimalInterface", package: "AnimalInterface"),
            .product(name: "Dynasty", package: "Dynasty"),
        ]),
    ],
    swiftLanguageModes: [.v5]
)
