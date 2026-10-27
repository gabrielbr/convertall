// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ConvertAll",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ConvertAll", targets: ["ConvertAll"]),
        .executable(name: "convertall", targets: ["ConvertAllCLI"]),
        .library(name: "ConvertAllCore", targets: ["ConvertAllCore"]),
    ],
    targets: [
        // Format catalogue, search, naming and pure-Swift codecs (QOI, PNM, TGA).
        // Everything that touches ImageIO / AppKit is behind `#if canImport`, so the
        // core also builds and tests on Linux CI.
        .target(name: "ConvertAllCore"),
        .executableTarget(name: "ConvertAll", dependencies: ["ConvertAllCore"]),
        // `convertall` command-line tool, bundled inside the app.
        .executableTarget(name: "ConvertAllCLI", dependencies: ["ConvertAllCore"]),
        .testTarget(name: "ConvertAllCoreTests", dependencies: ["ConvertAllCore"]),
    ]
)
