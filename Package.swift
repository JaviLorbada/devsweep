// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "devsweep",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DevSweepKit", targets: ["DevSweepKit"]),
        .executable(name: "devsweep", targets: ["devsweep"]),
        .executable(name: "DevSweepApp", targets: ["DevSweepApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(name: "DevSweepKit"),
        .executableTarget(
            name: "devsweep",
            dependencies: [
                "DevSweepKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "DevSweepApp",
            dependencies: [
                "DevSweepKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(name: "DevSweepKitTests", dependencies: ["DevSweepKit"], resources: [.copy("Fixtures")]),
        .testTarget(name: "DevSweepAppTests", dependencies: ["DevSweepApp", "DevSweepKit"]),
    ]
)
