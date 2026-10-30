import Foundation
import Synchronization

/// Scans and cleans one home folder with one set of tools.
public struct Engine: Sendable {
    public let config: ScanConfig
    public let dependencies: Dependencies
    public let policy: PathPolicy
    public var measurer: SizeMeasurer

    public var tools: Tools {
        self.dependencies.tools
    }

    /// Runs preflight: not root, and `config.home` must be a usable home folder.
    public init(
        config: ScanConfig,
        dependencies: Dependencies,
        measurer: SizeMeasurer = SizeMeasurer(),
        effectiveUserID: uid_t = geteuid()) throws(PreflightError)
    {
        self.config = config
        self.dependencies = dependencies
        self.policy = try PathPolicy.preflight(home: config.home, effectiveUserID: effectiveUserID)
        self.measurer = measurer
    }

    /// With the real disk and clock and these tools; what most tests use.
    init(
        config: ScanConfig,
        tools: Tools,
        measurer: SizeMeasurer = SizeMeasurer(),
        effectiveUserID: uid_t = geteuid()) throws(PreflightError)
    {
        try self.init(
            config: config,
            dependencies: Dependencies(tools: tools),
            measurer: measurer,
            effectiveUserID: effectiveUserID)
    }

    /// The items a scan covers, in report order.
    public var items: [Item] {
        Item.allCases.filter { !self.config.skipped.contains($0) }
    }

    /// The developer apps that are running and would have to quit before the
    /// Xcode items can be cleaned. Empty when those items are all skipped.
    public func runningAppsBlockingClean() async -> [DeveloperApp] {
        guard !self.config.skipsEverythingXcodeUses else { return [] }
        var running: [DeveloperApp] = []
        for app in DeveloperApp.allCases where await self.tools.runningApps.isRunning(app) {
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
                    await self.runConcurrently(continuation, options: options)
                } else {
                    await self.run(continuation, options: options)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeContext(_ continuation: AsyncStream<ScanEvent>.Continuation, options: ScanOptions) -> ScanContext {
        let folders = self.policy.projectFolders(self.config.projectDirectories)
        continuation.yield(.projectFolders(folders))
        return ScanContext(
            config: self.config,
            policy: self.policy,
            dependencies: self.dependencies,
            projects: ProjectSearch(roots: folders.roots, homeReal: self.policy.homeReal),
            measurer: self.measurer,
            concurrentFolders: options.concurrentFolders,
            warn: { continuation.yield(.warning($0)) })
    }

    /// The order items run in: the options' order, without skipped items,
    /// with anything the order leaves out at the end.
    private func ordered(_ options: ScanOptions) -> [Item] {
        let chosen = options.order.filter(self.items.contains)
        return chosen + self.items.filter { !chosen.contains($0) }
    }

    private func run(_ continuation: AsyncStream<ScanEvent>.Continuation, options: ScanOptions) async {
        let context = self.makeContext(continuation, options: options)

        var totalKilobytes: Int64 = 0
        for item in self.ordered(options) {
            if Task.isCancelled { return }
            continuation.yield(.started(item))
            let result = await Scanners.scanner(for: item).scan(in: context) { bytes in
                continuation.yield(.progress(item, bytes: bytes))
            }
            if Task.isCancelled { return }
            if !result.isEmpty { totalKilobytes += result.kilobytes }
            continuation.yield(.finished(result))
        }

        let free = DiskSpace.of(self.config.home)?.availableKilobytes ?? 0
        continuation.yield(.done(totalBytes: totalKilobytes * 1024, freeBytes: free * 1024))

        if self.config.includeExtras, !Task.isCancelled {
            await continuation.yield(.extras(ExtrasScanner.scan(in: context)))
        }
        if self.config.includeAndroid, !Task.isCancelled {
            await continuation.yield(.android(AndroidScanner().scan(in: context)))
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
        let context = self.makeContext(continuation, options: options)
        let order = self.ordered(options)
        let jobs = order
            .map(Job.item) + (self.config.includeExtras ? [.extras] : []) +
            (self.config.includeAndroid ? [.android] : [])
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
                case let .item(item):
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
                        let free = DiskSpace.of(self.config.home)?.availableKilobytes ?? 0
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
            let free = DiskSpace.of(self.config.home)?.availableKilobytes ?? 0
            continuation.yield(.done(totalBytes: 0, freeBytes: free * 1024))
        }
    }

    /// Free space on the home folder's volume.
    public func diskSpace() -> DiskSpace? {
        DiskSpace.of(self.config.home)
    }

    /// Lists installed Xcodes and simulator runtimes again, without scanning the items.
    public func extras() async -> Extras {
        await ExtrasScanner.scan(in: self.listingContext())
    }

    /// Lists what Android Studio keeps, without scanning the items.
    public func android() async -> AndroidReport {
        await AndroidScanner().scan(in: self.listingContext())
    }

    private func listingContext() -> ScanContext {
        ScanContext(
            config: self.config,
            policy: self.policy,
            dependencies: self.dependencies,
            projects: ProjectSearch(roots: [], homeReal: self.policy.homeReal),
            measurer: self.measurer,
            concurrentFolders: 1,
            warn: { _ in })
    }

    /// Removes a simulator runtime with `xcrun simctl runtime delete <id>`,
    /// the command the report shows. A scan never calls this; only an explicit
    /// request does. Ids that simctl could read as an option are refused.
    public func removeRuntime(_ runtime: SimulatorRuntime) async -> Bool {
        guard !runtime.id.isEmpty, !runtime.id.hasPrefix("-") else { return false }
        return await self.tools.simctl.deleteRuntime(runtime.id)
    }

    /// Removes a git worktree with `git worktree remove`, never forced, the
    /// command the report shows. A scan never calls this; only an explicit
    /// request does. Right before, it checks again what the listing said:
    /// both folders are inside the home folder and not symlinks, git still
    /// lists the folder as a worktree of that repository and not as locked,
    /// it has no changes, and a branch holds every commit in it. Git keeps
    /// the branch.
    public func removeWorktree(_ worktree: GitWorktree) async -> Bool {
        let git = self.tools.git
        guard let real = self.policy.safePath(worktree.path), self.policy.safePath(worktree.repository) != nil,
              let listing = await git.worktreeList(in: worktree.repository),
              let entry = WorktreeScanner.parse(listing).dropFirst()
                  .first(where: { FileSystem.physicalDirectory($0.path)?.bytesEqual(real) ?? false }),
              !entry.isLocked, !entry.isPrunable,
              let status = await git.status(in: entry.path), status.isEmpty
        else { return false }
        if entry.branch == nil {
            guard let refs = await git.refsContainingHead(in: entry.path), !refs.isEmpty else { return false }
        }
        // The path as git lists it, which is how git finds the worktree.
        return await git.removeWorktree(entry.path, from: worktree.repository)
    }
}
