import Synchronization

/// What every scanner gets to work with.
public struct ScanContext: Sendable {
    public let config: ScanConfig
    public let policy: PathPolicy
    public let dependencies: Dependencies
    public var tools: Tools {
        self.dependencies.tools
    }

    var files: any FileSystemAccess {
        self.dependencies.files
    }

    var clock: any WallClock {
        self.dependencies.clock
    }

    let projects: ProjectSearch
    let measurer: SizeMeasurer
    /// Folders of one item measured at the same time; 1 measures them in
    /// order on the scanning task, as the report always has.
    let concurrentFolders: Int
    let warn: @Sendable (String) -> Void

    init(
        config: ScanConfig,
        policy: PathPolicy,
        dependencies: Dependencies,
        projects: ProjectSearch,
        measurer: SizeMeasurer,
        concurrentFolders: Int = 1,
        warn: @escaping @Sendable (String) -> Void)
    {
        self.config = config
        self.policy = policy
        self.dependencies = dependencies
        self.projects = projects
        self.measurer = measurer
        self.concurrentFolders = concurrentFolders
        self.warn = warn
    }

    /// Measures each path, reporting the running total of all of them in
    /// bytes. The results come back in the order of `paths`.
    func measure(_ paths: [String], progress: @escaping @Sendable (Int64) -> Void) async -> [Measurement] {
        if self.concurrentFolders <= 1 || paths.count <= 1 {
            var results: [Measurement] = []
            var done: Int64 = 0
            for path in paths {
                if Task.isCancelled { break }
                let base = done * 1024
                let measured = self.measurer.measure(path) { progress(base + $0) }
                done += measured.kilobytes
                results.append(measured)
            }
            return results
        }
        let running = Mutex([Int64](repeating: 0, count: paths.count))
        return await withTaskGroup(of: (Int, Measurement).self) { group in
            var next = 0
            func add() {
                let index = next
                next += 1
                group.addTask {
                    let measured = await measurer.measureOffPool(paths[index]) { bytes in
                        progress(running.withLock { $0[index] = bytes; return $0.reduce(0, +) })
                    }
                    return (index, measured)
                }
            }
            while next < min(self.concurrentFolders, paths.count) {
                add()
            }
            var results = [Measurement?](repeating: nil, count: paths.count)
            while let (index, measured) = await group.next() {
                results[index] = measured
                if next < paths.count, !Task.isCancelled { add() }
            }
            return results.compactMap(\.self)
        }
    }

    var home: String {
        self.config.home
    }

    /// The resolved form of each path that passes the policy.
    func existing(_ paths: [String]) -> [String] {
        paths.compactMap(self.policy.safePath)
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
        let measured = await context.measure(paths, progress: progress)
        let kilobytes = measured.reduce(0) { $0 + $1.kilobytes }
        let known = measured.allSatisfy(\.readable)
        return await ItemResult(
            item: item,
            paths: paths,
            kilobytes: kilobytes,
            location: location(in: context),
            sizeKnown: known)
    }
}

/// The counterpart of `Scanner` for groups the app lists without cleaning
/// them yet. Same contract: paths come through the path policy and are
/// measured with the context's measurer, so a clean step can take them
/// later. Its result is a listing rather than an item's result, and no item
/// id stands for it, so the command line's items, `--skip` and report stay
/// as they are.
public protocol ListingScanner: Sendable {
    associatedtype Listing: Sendable
    func scan(in context: ScanContext) async -> Listing
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
        self.all.first { $0.item == item }!
    }
}
