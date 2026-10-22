/// Items that delete folders at fixed places in the home folder.
public struct FixedFoldersScanner: Scanner {
    public let item: Item
    /// Paths relative to the home folder.
    let relativePaths: [String]
    let describe: @Sendable (PathPolicy) -> String

    public func collect(in context: ScanContext) async -> [String] {
        context.existing(self.relativePaths.map { "\(context.home)/\($0)" })
    }

    public func location(in context: ScanContext) async -> String {
        self.describe(context.policy)
    }

    static let deviceInstallsPath =
        "Library/Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Caches/AppInstallationBinaryDeltas"

    public static let deviceInstalls = FixedFoldersScanner(
        item: .deviceInstalls,
        relativePaths: [deviceInstallsPath],
        describe: { $0.tilde("\($0.home)/\(deviceInstallsPath)") })

    public static let swiftpmCache = FixedFoldersScanner(
        item: .swiftpmCache,
        relativePaths: ["Library/Caches/org.swift.swiftpm"],
        describe: { $0.tilde("\($0.home)/Library/Caches/org.swift.swiftpm") })

    public static let npmCache = FixedFoldersScanner(
        item: .npmCache,
        relativePaths: [".npm/_cacache", ".npm/_npx"],
        describe: { "\($0.tilde("\($0.home)/.npm"))/_cacache and _npx" })

    public static let toolCaches = FixedFoldersScanner(
        item: .toolCaches,
        relativePaths: [
            "Library/Caches/CocoaPods",
            "Library/Caches/org.carthage.CarthageKit",
            "Library/Caches/Sourcery",
            "Library/Caches/ms-playwright",
            "Library/Caches/JetBrains/Toolbox/backup",
            "Library/Caches/JetBrains/Toolbox/download",
        ],
        describe: {
            "CocoaPods, Carthage, Sourcery, Playwright, JetBrains Toolbox in \($0.tilde("\($0.home)/Library/Caches"))"
        })
}
