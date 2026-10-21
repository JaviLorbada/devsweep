/// What every scanner gets to work with.
public struct ScanContext: Sendable {
    public let config: ScanConfig
    public let policy: PathPolicy
    public let tools: Tools
    let projects: ProjectSearch
    let measurer: SizeMeasurer
    let warn: @Sendable (String) -> Void

    init(
        config: ScanConfig,
        policy: PathPolicy,
        tools: Tools,
        projects: ProjectSearch,
        measurer: SizeMeasurer,
        warn: @escaping @Sendable (String) -> Void
    ) {
        self.config = config
        self.policy = policy
        self.tools = tools
        self.projects = projects
        self.measurer = measurer
        self.warn = warn
    }

    var home: String { config.home }

    /// The resolved form of each path that passes the policy.
    func existing(_ paths: [String]) -> [String] {
        paths.compactMap(policy.safePath)
    }
}

/// One type per item. A scanner lists the folders its item would delete and
/// measures them.
public protocol Scanner: Sendable {
    var item: Item { get }
    /// The dim line under the item's row.
    func location(in context: ScanContext) async -> String
    /// Paths the item would delete, each already through the path policy.
    func collect(in context: ScanContext) async -> [String]
    /// Lists and measures. The default sums `du -sk` over what `collect` lists.
    func scan(in context: ScanContext, progress: @escaping @Sendable (Int64) -> Void) async -> ItemResult
}

extension Scanner {
    public func scan(in context: ScanContext, progress: @escaping @Sendable (Int64) -> Void) async -> ItemResult {
        let paths = await collect(in: context).sortedUniqueBytewise()
        var kilobytes: Int64 = 0
        var known = true
        for path in paths {
            let base = kilobytes * 1024
            let measured = context.measurer.measure(path) { progress(base + $0) }
            kilobytes += measured.kilobytes
            known = known && measured.readable
        }
        return ItemResult(
            item: item,
            paths: paths,
            kilobytes: kilobytes,
            location: await location(in: context),
            sizeKnown: known
        )
    }
}

public enum Scanners {
    /// One scanner per item, in report order.
    public static let all: [any Scanner] = [
        DerivedDataScanner(),
        SimulatorsScanner(),
        FixedFoldersScanner.deviceInstalls,
        DeviceSupportScanner(),
        FixedFoldersScanner.swiftpmCache,
        ProjectBuildScanner.swiftpm,
        ProjectBuildScanner.xcode,
        ProjectBuildScanner.gradle,
        FixedFoldersScanner.npmCache,
        HomebrewScanner(),
        FixedFoldersScanner.toolCaches,
    ]

    public static func scanner(for item: Item) -> any Scanner {
        all.first { $0.item == item }!
    }
}
