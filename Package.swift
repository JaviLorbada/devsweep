// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "devclean",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DevCleanKit", targets: ["DevCleanKit"]),
        .executable(name: "devclean", targets: ["devclean"]),
        .executable(name: "DevCleanApp", targets: ["DevCleanApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.0"),
    ],
    targets: [
        .target(name: "DevCleanKit"),
        .executableTarget(
            name: "devclean",
            dependencies: [
                "DevCleanKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(name: "DevCleanApp", dependencies: ["DevCleanKit"]),
        .testTarget(name: "DevCleanKitTests", dependencies: ["DevCleanKit"]),
    ]
)
