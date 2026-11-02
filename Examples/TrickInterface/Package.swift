// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrickInterface",
    platforms: [.macOS(.v10_15)],
    products: [.library(name: "TrickInterface", type: .dynamic, targets: ["TrickInterface"])],
    dependencies: [.package(path: "../..")],
    targets: [
        .target(
            name: "TrickInterface",
            dependencies: [.product(name: "Dynasty", package: "Dynasty")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
