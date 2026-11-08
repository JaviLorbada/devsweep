import DevSweepKit
import Foundation
import Observation
import SwiftUI

/// What the scan found, one row per item, and the scan that fills them:
/// the one source of truth the window's screens and the menu bar read.
///
/// Only it changes the rows. A clean changes them through the methods under
/// "Cleaning", between `beginCleaning()` and `endCleaning()`, and a scan and
/// a clean never run at once.
@MainActor
@Observable
final class ScanModel: ScanResults, Listings, ScanRows {
    let volumeName: String
    let preferences: Preferences
    /// Rebuilt from the preferences when a scan starts. The shared models
    /// call it; views ask this model instead.
    private(set) var engine: Engine?
    private(set) var startupError: String?
    private(set) var rows: [Item: ScanRow] = [:]
    private(set) var scanOrder: [Item] = []
    private(set) var isScanning = false
    /// A clean is running; no scan starts until it ends.
    private(set) var isCleaning = false
    private(set) var isLoadingExtras = false
    private(set) var isLoadingAndroid = false
    private(set) var lastScan: Date?
    /// When the results on screen came from the last launch's scan.
    private(set) var previousScanDate: Date?
    /// Ticks every half minute so "3 minutes ago" stays true.
    private(set) var now = Date()
    private(set) var diskSpace: DiskSpace?
    /// Installed Xcodes, runtimes and worktrees.
    private(set) var extras: Extras?
    /// What Android Studio keeps.
    private(set) var android: AndroidReport?
    private(set) var projectFolders: ProjectFolders?
    private(set) var warnings: [String] = []
    /// How long the last scan took, in seconds since it started: until every
    /// item was measured, and until the extras were listed too.
    private(set) var scanTiming: (items: Double, total: Double)?

    /// What the coordinator hears from a scan: it started; its items are
    /// all measured, or it stopped before that; everything is in and kept.
    @ObservationIgnored var onStart: (() -> Void)?
    @ObservationIgnored var onItemsMeasured: ((_ stopped: Bool) -> Void)?
    @ObservationIgnored var onFinished: (() -> Void)?

    private let environment: [String: String]
    private let dependencies: Dependencies
    private let store: (any ScanMemoryStore)?
    @ObservationIgnored private var scanStarted: ContinuousClock.Instant?
    @ObservationIgnored private var itemsDone: Double?
    @ObservationIgnored private var extrasDone: Double?
    @ObservationIgnored private var androidDone: Double?
    /// Progress that arrived since the screen last showed it.
    @ObservationIgnored private var pendingProgress: [Item: Int64] = [:]
    @ObservationIgnored private var progressFlush: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?

    /// - Parameter store: where the last scan is kept for the next launch;
    ///   the home's own file when nil.
    init(
        environment: [String: String],
        store: (any ScanMemoryStore)?,
        preferences: Preferences,
        dependencies: Dependencies)
    {
        self.environment = environment
        self.dependencies = dependencies
        self.preferences = preferences
        let (engine, startupError) = Self.makeEngine(
            preferences: preferences,
            environment: environment,
            dependencies: dependencies)
        self.engine = engine
        self.startupError = startupError
        self.store = store ?? engine.map { ScanStore.standard(home: $0.config.home) }
        self.volumeName = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]))?
            .volumeLocalizedName ?? "Macintosh HD"
        self.rows = Dictionary(uniqueKeysWithValues: (engine?.items ?? []).map { ($0, ScanRow(item: $0)) })
        self.scanOrder = engine?.items ?? []
        self.diskSpace = engine?.diskSpace()
        self.restorePreviousScan()
    }

    private static func makeEngine(
        preferences: Preferences,
        environment: [String: String],
        dependencies: Dependencies) -> (Engine?, String?)
    {
        var config = preferences.scanConfig(environment: environment)
        #if DEBUG
        if let skip = environment["DEVSWEEP_SKIP"], let items = try? ScanConfig.parseSkip(skip) {
            config.skipped.formUnion(items)
        }
        #endif
        do {
            return try (Engine(config: config, dependencies: dependencies), nil)
        } catch {
            return (nil, error.description)
        }
    }

    // MARK: Scanning

    func scan() {
        guard !self.isScanning, !self.isCleaning else { return }
        // Preferences changed since the last scan apply from this one.
        (self.engine, self.startupError) = Self.makeEngine(
            preferences: self.preferences,
            environment: self.environment,
            dependencies: self.dependencies)
        guard let engine else { return }
        // What was on screen becomes the dimmed "last scan" until replaced.
        self.rows = Dictionary(uniqueKeysWithValues: engine.items.map { item in
            var row = ScanRow(item: item)
            row.previous = self.rows[item]?.result ?? self.rows[item]?.previous
            return (item, row)
        })
        if self.lastScan != nil { self.previousScanDate = self.lastScan }
        self.scanOrder = engine.items
        self.warnings = []
        self.isScanning = true
        self.isLoadingExtras = engine.config.includeExtras
        self.isLoadingAndroid = engine.config.includeAndroid
        self.scanStarted = .now
        self.itemsDone = nil
        self.extrasDone = nil
        self.androidDone = nil
        self.scanTiming = nil
        self.onStart?()

        self.scanTask = Task {
            for await event in engine.scan(.interactive) {
                self.apply(event)
            }
            self.flushProgress()
            self.finishScan()
            self.scanTask = nil
        }
    }

    func stopScan() {
        self.scanTask?.cancel()
    }

    /// The clock for "3 minutes ago", and the free space for the menu bar.
    func tick(now: Date) {
        self.now = now
        self.diskSpace = self.engine?.diskSpace() ?? self.diskSpace
    }

    /// Lists the Xcodes, runtimes and worktrees again.
    func refreshExtras() async {
        guard let engine else { return }
        self.isLoadingExtras = true
        let fresh = await engine.extras()
        withAnimation(Motion.animation()) { self.extras = fresh }
        self.isLoadingExtras = false
    }

    /// Removes a runtime through simctl, then lists the extras again.
    /// Whether simctl removed it.
    func removeRuntime(_ runtime: SimulatorRuntime) async -> Bool {
        guard let engine else { return false }
        let removed = await engine.removeRuntime(runtime)
        if removed { await self.extrasChanged() }
        return removed
    }

    /// Removes a worktree with git, then lists the extras again. Whether git
    /// removed it.
    func removeWorktree(_ worktree: GitWorktree) async -> Bool {
        guard let engine else { return false }
        let removed = await engine.removeWorktree(worktree)
        if removed { await self.extrasChanged() }
        return removed
    }

    private func extrasChanged() async {
        await self.refreshExtras()
        self.diskSpace = self.engine?.diskSpace()
    }

    private func apply(_ event: ScanEvent) {
        switch event {
        case let .projectFolders(folders):
            self.projectFolders = folders
        case let .started(item):
            withAnimation(Motion.animation(.easeInOut(duration: 0.25))) { self.rows[item]?.state = .measuring }
        case let .progress(item, bytes):
            // Several walks report thousands of times a second; the screen
            // shows the latest count about ten times a second.
            self.pendingProgress[item] = bytes
            if self.progressFlush == nil {
                self.progressFlush = Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    self.flushProgress()
                }
            }
        case let .warning(message):
            self.warnings.append(message)
        case let .finished(result):
            self.pendingProgress[result.item] = nil
            withAnimation(Motion.animation(.easeInOut(duration: 0.4))) {
                self.rows[result.item]?.result = result
                self.rows[result.item]?.state = .measured
            }
        case .done:
            self.itemsDone = self.secondsSinceScanStarted
            self.diskSpace = self.engine?.diskSpace()
            self.lastScan = Date()
            self.now = Date()
            self.previousScanDate = nil
            withAnimation(Motion.animation()) { self.isScanning = false }
            self.onItemsMeasured?(false)
            self.finishTiming()
        case let .extras(extras):
            withAnimation(Motion.animation()) { self.extras = extras }
            self.isLoadingExtras = false
            self.extrasDone = self.secondsSinceScanStarted
            self.finishTiming()
        case let .android(report):
            withAnimation(Motion.animation()) { self.android = report }
            self.isLoadingAndroid = false
            self.androidDone = self.secondsSinceScanStarted
            self.finishTiming()
        }
    }

    private func flushProgress() {
        self.progressFlush = nil
        for (item, bytes) in self.pendingProgress where self.rows[item]?.state == .measuring {
            self.rows[item]?.progressBytes = bytes
        }
        self.pendingProgress = [:]
    }

    private var secondsSinceScanStarted: Double? {
        self.scanStarted.map { start in
            let elapsed = ContinuousClock.now - start
            return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        }
    }

    /// Once the items, the extras and Android Studio are all in: the timing,
    /// and a copy of the results for the next launch.
    private func finishTiming() {
        guard let itemsDone,
              extrasDone != nil || !(engine?.config.includeExtras ?? false),
              androidDone != nil || !(engine?.config.includeAndroid ?? false) else { return }
        self.scanTiming = (itemsDone, max(itemsDone, self.extrasDone ?? 0, self.androidDone ?? 0))
        self.saveScan()
        self.onFinished?()
    }

    private func finishScan() {
        self.isLoadingExtras = false
        self.isLoadingAndroid = false
        guard self.isScanning else { return }
        // Stopped before the end: what wasn't reached stays unmeasured.
        withAnimation(Motion.animation()) {
            for item in self.scanOrder where !(self.rows[item]?.wasMeasured ?? false) {
                self.rows[item]?.state = .notMeasured
                self.rows[item]?.progressBytes = 0
            }
            self.isScanning = false
        }
        self.lastScan = Date()
        self.diskSpace = self.engine?.diskSpace()
        self.onItemsMeasured?(true)
    }
}

// MARK: What the screens read

extension ScanModel {
    /// The rows' order, totals and weights.
    var tally: Tally {
        Tally(order: self.scanOrder, rows: self.rows)
    }

    /// What the status lines are written from.
    var statusFacts: StatusText.Facts {
        let tally = self.tally
        return StatusText.Facts(
            startupError: self.startupError,
            isScanning: self.isScanning,
            measured: tally.measuredCount,
            items: tally.rows.count,
            notMeasured: tally.notMeasuredCount,
            showsPrevious: tally.showsPrevious,
            lastScan: self.lastScan,
            previousScanDate: self.previousScanDate,
            now: self.now)
    }

    /// Whether there is a home to scan.
    var canScan: Bool {
        self.engine != nil
    }

    /// Whether Scan Again, or Stop, can be used: not while cleaning, which
    /// `scan()` waits out by doing nothing.
    var canScanOrStop: Bool {
        self.engine != nil && !self.isCleaning
    }

    /// Whether a scan's task is still winding down, even after `isScanning` turned false.
    var isScanTaskRunning: Bool {
        self.scanTask != nil
    }

    /// The home folder scanned.
    var home: String? {
        self.engine?.config.home
    }

    /// The path rule, which writes paths the way the window shows them.
    var policy: PathPolicy? {
        self.engine?.policy
    }

    /// `path` with the home folder as `~`.
    func tilde(_ path: String) -> String {
        self.engine?.policy.tilde(path) ?? path
    }

    /// What `parts` of `item` take, as this scan measured them.
    func kilobytes(of parts: Set<ItemPart>, in item: Item) -> Int64 {
        guard let result = self.rows[item]?.result else { return 0 }
        return parts.reduce(0) { $0 + result.kilobytes(of: $1) }
    }
}

// MARK: The last scan, for the next launch

extension ScanModel {
    /// Shows the last launch's scan of this home, dimmed, until this one replaces it.
    private func restorePreviousScan() {
        guard let engine, let saved = store?.load(home: engine.policy.homeReal) else { return }
        for result in saved.results {
            self.rows[result.item]?.previous = result
        }
        self.extras = saved.extras
        self.android = saved.android
        self.previousScanDate = saved.date
    }

    /// Keeps this scan's results for the next launch. Cleaned items are kept
    /// as found nothing, since they are gone.
    private func saveScan() {
        guard let engine, let store else { return }
        let results: [ItemResult] = self.scanOrder.compactMap { item in
            guard let row = rows[item], var result = row.result, row.wasMeasured else { return nil }
            if row.state == .cleaned {
                result.paths = []
                result.kilobytes = 0
                result.derivedData = nil
            }
            return result
        }
        guard results.count == self.scanOrder.count else { return }
        let scan = SavedScan(
            date: lastScan ?? Date(),
            home: engine.policy.homeReal,
            results: results,
            extras: self.extras,
            android: self.android)
        try? store.save(scan)
    }
}

// MARK: Cleaning

/// The rows during a clean: what CleaningModel asks for, between
/// `beginCleaning()` and `endCleaning(warnings:)`.
extension ScanModel {
    /// Takes the rows for a clean: false while scanning or cleaning, or with
    /// no home to clean in.
    func beginCleaning() -> Bool {
        guard self.engine != nil, !self.isScanning, !self.isCleaning else { return false }
        self.isCleaning = true
        return true
    }

    /// Gives the rows back after a clean, with the free space measured again
    /// and the results kept for the next launch. `warnings` join the scan's.
    func endCleaning(warnings: [String]) {
        self.isCleaning = false
        self.warnings += warnings
        self.diskChanged()
    }

    /// Something was cleaned or put back: the free space and the kept results follow.
    func diskChanged() {
        self.diskSpace = self.engine?.diskSpace() ?? self.diskSpace
        self.saveScan()
    }

    /// `item`'s row starts cleaning; `kilobytes` is what it will take, when
    /// only parts of it go.
    func startCleaning(_ item: Item, kilobytes: Int64? = nil) {
        withAnimation(Motion.animation()) {
            self.rows[item]?.state = .cleaning
            self.rows[item]?.cleaningKilobytes = kilobytes
        }
    }

    /// While deleting, how much of `item` is gone so far.
    func cleaningProgress(_ item: Item, removedBytes: Int64) {
        self.rows[item]?.removedBytes = removedBytes
    }

    /// The whole of `item` went: with `outcome` when something was removed,
    /// back to measured when nothing was.
    func finishCleaning(_ item: Item, outcome: CleanOutcome?) {
        withAnimation(Motion.animation(.easeInOut(duration: 0.4))) {
            self.rows[item]?.removedBytes = 0
            if let outcome {
                self.rows[item]?.state = .cleaned
                self.rows[item]?.outcome = outcome
            } else {
                self.rows[item]?.state = .measured
            }
        }
    }

    /// Parts of `item` went, and `left` is what remains of it.
    func finishCleaningParts(_ item: Item, left: ItemResult) {
        withAnimation(Motion.animation(.easeInOut(duration: 0.4))) {
            self.rows[item]?.removedBytes = 0
            self.rows[item]?.result = left
            self.rows[item]?.state = .measured
            self.rows[item]?.cleaningKilobytes = nil
        }
    }

    /// What cleaning `item` moved to the Trash came back.
    func putBack(_ item: Item) {
        withAnimation(Motion.animation(.easeInOut(duration: 0.4))) {
            self.rows[item]?.state = .measured
            self.rows[item]?.outcome = nil
        }
    }

    /// Parts of `item` came back from the Trash, and it is `whole` again.
    func putBackParts(_ item: Item, whole: ItemResult) {
        withAnimation(Motion.animation(.easeInOut(duration: 0.4))) {
            self.rows[item]?.result = whole
        }
    }
}

// MARK: Without scanning, for tests and screenshots

#if DEBUG
extension ScanModel {
    /// Shows results as if a scan had just measured them.
    func showResults(_ results: [ItemResult]) {
        for result in results {
            self.rows[result.item]?.result = result
            self.rows[result.item]?.state = .measured
        }
        self.lastScan = Date()
    }

    /// Shows these listings as if a scan had just listed them.
    func showListings(extras: Extras?, android: AndroidReport?) {
        self.extras = extras
        self.android = android
    }

    /// Puts the rows back to the moment `measured` items were done.
    func rewindScan(toMeasured measured: Int) {
        for (index, item) in self.scanOrder.enumerated() where index >= measured {
            guard var row = rows[item] else { continue }
            row.previous = row.result
            row.progressBytes = index == measured ? row.kilobytes * 1024 / 3 : 0
            row.state = index == measured ? .measuring : .waiting
            row.result = nil
            self.rows[item] = row
        }
        self.isScanning = true
    }
}
#endif
