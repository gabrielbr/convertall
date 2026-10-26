// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ConvertAll",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ConvertAll", targets: ["ConvertAll"]),
        .library(name: "ConvertAllCore", targets: ["ConvertAllCore"]),
    ],
    targets: [
        // Format catalogue, search, naming and pure-Swift codecs (QOI, PNM, TGA).
        // Everything that touches ImageIO / AppKit is behind `#if canImport`, so the
        // core also builds and tests on Linux CI.
        .target(name: "ConvertAllCore"),
        .executableTarget(name: "ConvertAll", dependencies: ["ConvertAllCore"]),
        .testTarget(name: "ConvertAllCoreTests", dependencies: ["ConvertAllCore"]),
    ]
)
