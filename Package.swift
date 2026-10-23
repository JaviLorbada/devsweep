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
        .executableTarget(name: "DevSweepApp", dependencies: ["DevSweepKit"]),
        .testTarget(name: "DevSweepKitTests", dependencies: ["DevSweepKit"], resources: [.copy("Fixtures")]),
        .testTarget(name: "DevSweepAppTests", dependencies: ["DevSweepApp", "DevSweepKit"]),
    ]
)
