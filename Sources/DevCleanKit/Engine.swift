import Foundation
import Synchronization

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

    /// Scans every item that isn't skipped, then the extras when asked.
    /// Cancelling the consuming task stops the scan.
    ///
    /// With `.report`, the default, items go one at a time in report order and
    /// events arrive as `ScanEvent` describes. With more concurrency, several
    /// items are `started` before others `finish`, and `extras` can arrive
    /// before `done`.
    public func scan(_ options: ScanOptions = .report) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                if options.concurrentItems > 1 {
                    await runConcurrently(continuation, options: options)
                } else {
                    await run(continuation, options: options)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeContext(_ continuation: AsyncStream<ScanEvent>.Continuation, options: ScanOptions) -> ScanContext {
        let folders = policy.projectFolders(config.projectDirectories)
        continuation.yield(.projectFolders(folders))
        return ScanContext(
            config: config,
            policy: policy,
            tools: tools,
            projects: ProjectSearch(roots: folders.roots, homeReal: policy.homeReal),
            measurer: measurer,
            concurrentFolders: options.concurrentFolders,
            warn: { continuation.yield(.warning($0)) }
        )
    }

    /// The order items run in: the options' order, without skipped items,
    /// with anything the order leaves out at the end.
    private func ordered(_ options: ScanOptions) -> [Item] {
        let chosen = options.order.filter(items.contains)
        return chosen + items.filter { !chosen.contains($0) }
    }

    private func run(_ continuation: AsyncStream<ScanEvent>.Continuation, options: ScanOptions) async {
        let context = makeContext(continuation, options: options)

        var totalKilobytes: Int64 = 0
        for item in ordered(options) {
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
        if config.includeAndroid, !Task.isCancelled {
            continuation.yield(.android(await AndroidScanner().scan(in: context)))
        }
    }

    private enum Job: Sendable {
        case item(Item)
        case extras
        case android
    }

    /// Up to `concurrentItems` jobs at a time, in the options' order, with
    /// the extras as one more job. `done` goes out when the last item finishes.
    private func runConcurrently(_ continuation: AsyncStream<ScanEvent>.Continuation, options: ScanOptions) async {
        let context = makeContext(continuation, options: options)
        let order = ordered(options)
        let jobs = order.map(Job.item) + (config.includeExtras ? [.extras] : []) + (config.includeAndroid ? [.android] : [])
        let progress = Mutex((finished: 0, kilobytes: Int64(0)))

        await withTaskGroup(of: Void.self) { group in
            var pending = jobs.makeIterator()
            func perform(_ job: Job) async {
                switch job {
                case .extras:
                    let extras = await ExtrasScanner.scan(in: context)
                    if !Task.isCancelled { continuation.yield(.extras(extras)) }
                case .android:
                    let report = await AndroidScanner().scan(in: context)
                    if !Task.isCancelled { continuation.yield(.android(report)) }
                case .item(let item):
                    continuation.yield(.started(item))
                    let result = await Scanners.scanner(for: item).scan(in: context) { bytes in
                        continuation.yield(.progress(item, bytes: bytes))
                    }
                    guard !Task.isCancelled else { return }
                    continuation.yield(.finished(result))
                    let (finished, total) = progress.withLock { state in
                        state.finished += 1
                        if !result.isEmpty { state.kilobytes += result.kilobytes }
                        return (state.finished, state.kilobytes)
                    }
                    if finished == order.count {
                        let free = DiskSpace.of(config.home)?.availableKilobytes ?? 0
                        continuation.yield(.done(totalBytes: total * 1024, freeBytes: free * 1024))
                    }
                }
            }
            for _ in 0..<options.concurrentItems {
                guard let job = pending.next() else { break }
                group.addTask { await perform(job) }
            }
            while await group.next() != nil {
                if Task.isCancelled { group.cancelAll(); continue }
                if let job = pending.next() {
                    group.addTask { await perform(job) }
                }
            }
        }
        if order.isEmpty {
            let free = DiskSpace.of(config.home)?.availableKilobytes ?? 0
            continuation.yield(.done(totalBytes: 0, freeBytes: free * 1024))
        }
    }

    /// Free space on the home folder's volume.
    public func diskSpace() -> DiskSpace? {
        DiskSpace.of(config.home)
    }

    /// Lists installed Xcodes and simulator runtimes again, without scanning the items.
    public func extras() async -> Extras {
        await ExtrasScanner.scan(in: listingContext())
    }

    /// Lists what Android Studio keeps, without scanning the items.
    public func android() async -> AndroidReport {
        await AndroidScanner().scan(in: listingContext())
    }

    private func listingContext() -> ScanContext {
        ScanContext(
            config: config,
            policy: policy,
            tools: tools,
            projects: ProjectSearch(roots: [], homeReal: policy.homeReal),
            measurer: measurer,
            concurrentFolders: 1,
            warn: { _ in }
        )
    }

    /// Removes a simulator runtime with `xcrun simctl runtime delete <id>`,
    /// the command the report shows. A scan never calls this; only an explicit
    /// request does. Ids that simctl could read as an option are refused.
    public func removeRuntime(_ runtime: SimulatorRuntime) async -> Bool {
        guard !runtime.id.isEmpty, !runtime.id.hasPrefix("-") else { return false }
        return await tools.simctl.deleteRuntime(runtime.id)
    }
}
