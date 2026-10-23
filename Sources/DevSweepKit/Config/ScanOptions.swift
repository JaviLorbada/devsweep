/// How a scan runs, as opposed to what it looks at.
public struct ScanOptions: Sendable, Equatable {
    /// How many items are measured at the same time.
    public var concurrentItems: Int
    /// How many folders of one item (build folders, DerivedData's parts) are
    /// measured at the same time.
    public var concurrentFolders: Int
    /// The order items start in.
    public var order: [Item]

    public init(concurrentItems: Int, concurrentFolders: Int, order: [Item]) {
        self.concurrentItems = max(1, concurrentItems)
        self.concurrentFolders = max(1, concurrentFolders)
        self.order = order
    }

    /// The report's way, one item after another in report order, exactly as
    /// the bash script ran. The command line uses this.
    public static let report = ScanOptions(concurrentItems: 1, concurrentFolders: 1, order: Item.allCases)

    /// For the window: several items at once, the quick ones first so the
    /// ring fills within seconds, DerivedData last so the big one lands at the
    /// end. Installed Xcodes and runtimes are listed alongside.
    public static let interactive = ScanOptions(concurrentItems: 4, concurrentFolders: 4, order: Item.quickestFirst)
}

extension Item {
    /// Fixed folders first, then what brew and simctl report, then the project
    /// folder searches, then DerivedData.
    public static let quickestFirst: [Item] = [
        .npmCache, .toolCaches, .deviceInstalls, .simulators, .deviceSupport, .swiftpmCache,
        .homebrew, .gradleBuilds, .xcodeBuilds, .swiftpmBuilds, .derivedData,
    ]
}
