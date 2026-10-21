import Foundation

/// Scans and cleans one home folder with one set of tools.
public struct Engine: Sendable {
    public let config: ScanConfig
    public let tools: Tools
    public let policy: PathPolicy
    public var measurer: SizeMeasurer

    /// Runs preflight: not root, and `config.home` must be a usable home folder.
    public init(
        config: ScanConfig,
        tools: Tools,
        measurer: SizeMeasurer = SizeMeasurer(),
        effectiveUserID: uid_t = geteuid()
    ) throws(PreflightError) {
        self.config = config
        self.tools = tools
        self.policy = try PathPolicy.preflight(home: config.home, effectiveUserID: effectiveUserID)
        self.measurer = measurer
    }

    /// The items a scan covers, in report order.
    public var items: [Item] {
        Item.allCases.filter { !config.skipped.contains($0) }
    }

    /// The developer apps that are running and would have to quit before the
    /// Xcode items can be cleaned. Empty when those items are all skipped.
    public func runningAppsBlockingClean() async -> [DeveloperApp] {
        guard !config.skipsEverythingXcodeUses else { return [] }
        var running: [DeveloperApp] = []
        for app in DeveloperApp.allCases where await tools.runningApps.isRunning(app) {
            running.append(app)
        }
        return running
    }

    /// Scans every item that isn't skipped, one at a time in report order, then
    /// the extras when asked. Cancelling the consuming task stops the scan.
    public func scan() -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                await run(continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ continuation: AsyncStream<ScanEvent>.Continuation) async {
        let folders = policy.projectFolders(config.projectDirectories)
        continuation.yield(.projectFolders(folders))

        let context = ScanContext(
            config: config,
            policy: policy,
            tools: tools,
            projects: ProjectSearch(roots: folders.roots, homeReal: policy.homeReal),
            measurer: measurer,
            warn: { continuation.yield(.warning($0)) }
        )

        var totalKilobytes: Int64 = 0
        for item in items {
            if Task.isCancelled { return }
            continuation.yield(.started(item))
            let result = await Scanners.scanner(for: item).scan(in: context) { bytes in
                continuation.yield(.progress(item, bytes: bytes))
            }
            if Task.isCancelled { return }
            if !result.isEmpty { totalKilobytes += result.kilobytes }
            continuation.yield(.finished(result))
        }

        let free = DiskSpace.of(config.home)?.availableKilobytes ?? 0
        continuation.yield(.done(totalBytes: totalKilobytes * 1024, freeBytes: free * 1024))

        if config.includeExtras, !Task.isCancelled {
            continuation.yield(.extras(await ExtrasScanner.scan(in: context)))
        }
    }

    /// Free space on the home folder's volume.
    public func diskSpace() -> DiskSpace? {
        DiskSpace.of(config.home)
    }
}
