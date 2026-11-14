import Foundation
import Synchronization
@testable import DevSweepApp

// The kit's clean results have no public initializers: only the kit makes
// them. The fake cleaner makes them as the kit would.
@testable import DevSweepKit

// MARK: The models, as the protocols show them

/// What a scan found, as a test sets it: rows, all measured, and the facts
/// the status lines are written from.
@MainActor
final class FakeScanResults: ScanResults {
    var tally: Tally
    var statusFacts = StatusText.Facts()

    init(_ results: [ItemResult] = []) {
        self.tally = .measured(results)
    }
}

/// What a scan listed, as a test sets it. simctl and git remove what they
/// are asked to unless `removes` is false; either way, what was asked is kept.
@MainActor
final class FakeListings: Listings {
    var extras: Extras?
    var android: AndroidReport?
    var isLoadingExtras = false
    var isLoadingAndroid = false
    var policy: PathPolicy?
    var removes = true
    private(set) var askedToRemove: [String] = []

    init(extras: Extras? = nil, android: AndroidReport? = nil) {
        self.extras = extras
        self.android = android
    }

    func removeRuntime(_ runtime: SimulatorRuntime) async -> Bool {
        self.askedToRemove.append(runtime.id)
        if self.removes { self.extras?.runtimes.removeAll { $0.id == runtime.id } }
        return self.removes
    }

    func removeWorktree(_ worktree: GitWorktree) async -> Bool {
        self.askedToRemove.append(worktree.path)
        if self.removes { self.extras?.worktrees.removeAll { $0.path == worktree.path } }
        return self.removes
    }
}

/// The scan's rows as a test sets them, changed the way `ScanModel` changes
/// them, with a fake cleaner behind them. `cleansBegun` counts the cleans
/// and put backs that took the rows; the cleaner never touches the disk.
/// The flow tests clean for real, on a fake home.
@MainActor
final class FakeScanRows: ScanRows {
    var rows: [Item: ScanRow]
    var isScanning = false
    private(set) var isCleaning = false
    private(set) var cleansBegun = 0
    private(set) var warnings: [String] = []
    let cleaner: FakeCleaner

    init(_ results: [ItemResult], cleaner: FakeCleaner = FakeCleaner()) {
        self.rows = measuredRows(results)
        self.cleaner = cleaner
    }

    func beginCleaning() -> (any Cleaner)? {
        guard !self.isScanning, !self.isCleaning else { return nil }
        self.isCleaning = true
        self.cleansBegun += 1
        return self.cleaner
    }

    func endCleaning(warnings: [String]) {
        self.isCleaning = false
        self.warnings += warnings
    }

    func startCleaning(_ item: Item, kilobytes: Int64?) {
        self.rows[item]?.state = .cleaning
        self.rows[item]?.cleaningKilobytes = kilobytes
    }

    func cleaningProgress(_ item: Item, removedBytes: Int64) {
        self.rows[item]?.removedBytes = removedBytes
    }

    func finishCleaning(_ item: Item, outcome: CleanOutcome?) {
        self.rows[item]?.removedBytes = 0
        self.rows[item]?.state = outcome == nil ? .measured : .cleaned
        self.rows[item]?.outcome = outcome
    }

    func finishCleaningParts(_ item: Item, left: ItemResult) {
        self.rows[item]?.removedBytes = 0
        self.rows[item]?.result = left
        self.rows[item]?.state = .measured
        self.rows[item]?.cleaningKilobytes = nil
    }

    func putBack(_ item: Item) {
        self.rows[item]?.state = .measured
        self.rows[item]?.outcome = nil
    }

    func putBackParts(_ item: Item, whole: ItemResult) {
        self.rows[item]?.result = whole
    }

    func tilde(_ path: String) -> String {
        path
    }
}

/// Cleans without touching the disk: each folder it is asked for goes, to a
/// made-up Trash or for good as asked, unless the test lists it in
/// `failing`. Put Back brings back whatever went to the Trash. It records
/// the items it cleaned and how many put backs it was asked for.
final class FakeCleaner: Cleaner, @unchecked Sendable {
    private let state = Mutex<(cleaned: [Item], putBacks: Int)>(([], 0))
    private let failing: Set<String>

    init(failing: Set<String> = []) {
        self.failing = failing
    }

    var cleaned: [Item] {
        self.state.withLock { $0.cleaned }
    }

    var putBacks: Int {
        self.state.withLock { $0.putBacks }
    }

    func clean(_ result: ItemResult, mode: CleanMode, progress: (@Sendable (Int64) -> Void)?) async -> CleanOutcome {
        self.state.withLock { $0.cleaned.append(result.item) }
        progress?(result.kilobytes * 1024)
        return self.removing(result.paths, of: result.item, mode: mode)
    }

    func clean(
        _ parts: Set<ItemPart>,
        of result: ItemResult,
        mode: CleanMode,
        progress: (@Sendable (Int64) -> Void)?) async -> PartsCleanOutcome
    {
        self.state.withLock { $0.cleaned.append(result.item) }
        var paths: [ItemPart: [String]] = [:]
        for part in parts {
            switch part {
            case let .folder(folder): paths[part] = [folder]
            default: paths[part] = ["/fake/\(result.item.rawValue)/\(part)"]
            }
        }
        return PartsCleanOutcome(
            outcome: self.removing(paths.values.flatMap(\.self), of: result.item, mode: mode),
            paths: paths)
    }

    func putBack(_ outcome: CleanOutcome) async -> PutBackOutcome {
        self.state.withLock { $0.putBacks += 1 }
        return PutBackOutcome(restored: outcome.removed.filter { $0.trashed != nil }.map(\.original), failed: [])
    }

    private func removing(_ folders: [String], of item: Item, mode: CleanMode) -> CleanOutcome {
        var outcome = CleanOutcome(item: item, mode: mode)
        for folder in folders {
            if self.failing.contains(folder) {
                outcome.failed.append(folder)
                outcome.warnings.append("Couldn't remove \(folder).")
            } else {
                outcome.removed.append(.init(original: folder, trashed: mode == .trash ? "/Trash/\(folder)" : nil))
            }
        }
        return outcome
    }
}

/// What is ticked, as a test sets it.
@MainActor
final class FakeMarking: Marking {
    var parts: [Item: Set<ItemPart>] = [:]
    private(set) var cleanedItems: [Item] = []

    func markedParts(of item: Item) -> Set<ItemPart> {
        self.parts[item] ?? []
    }

    func cleaned(_ item: Item) {
        self.cleanedItems.append(item)
    }

    func cleaned(_ parts: Set<ItemPart>, of item: Item) {
        self.parts[item]?.subtract(parts)
    }
}

/// Xcode and Simulator as the model sees them: open as a test says, and
/// quitting when asked unless `quits` is false. Quitting records what was asked.
@MainActor
final class FakeRunningApps: RunningApps {
    /// Settable, so a test can open Xcode between a question and its answer.
    var running: Set<DeveloperApp>
    private(set) var askedToQuit: [[DeveloperApp]] = []
    private let quits: Bool

    init(_ running: Set<DeveloperApp> = [], quits: Bool = true) {
        self.running = running
        self.quits = quits
    }

    func refresh() async {}

    func quit(_ apps: [DeveloperApp]) async -> Bool {
        self.askedToQuit.append(apps)
        if self.quits { self.running.subtract(apps) }
        return self.quits
    }
}

/// This session's totals, as a test sets them.
@MainActor
final class FakeCleaningTotals: CleaningTotals {
    var trashedThisSession: Int64 = 0
    var deletedThisSession: Int64 = 0
}

/// The screen on show, as a test sets it.
@MainActor
final class FakeNavigation: Navigation {
    var screen: Screen

    init(_ screen: Screen = .overview) {
        self.screen = screen
    }

    func show(_ screen: Screen) {
        self.screen = screen
    }
}

// MARK: macOS, as the app's seams show it

/// Xcode and Simulator as macOS reports them, for the running apps model and
/// the whole app: which run, and whether asking them to quit works.
/// Quitting records what was asked.
final class FakeDeveloperApps: RunningAppsChecking, AppQuitting, @unchecked Sendable {
    private let state: Mutex<(running: Set<DeveloperApp>, quits: Bool, asked: [[DeveloperApp]])>

    init(running: Set<DeveloperApp> = [], quits: Bool = true) {
        self.state = Mutex((running, quits, []))
    }

    var asked: [[DeveloperApp]] {
        self.state.withLock { $0.asked }
    }

    func isRunning(_ app: DeveloperApp) async -> Bool {
        self.state.withLock { $0.running.contains(app) }
    }

    func quit(_ apps: [DeveloperApp]) async -> Bool {
        self.state.withLock { state in
            state.asked.append(apps)
            if state.quits { state.running.subtract(apps) }
            return state.quits
        }
    }
}

/// Keeps what would have been posted.
final class RecordingPoster: NotificationPoster {
    let posted = Mutex<[String]>([])
    func post(title: String, body: String) async { self.posted.withLock { $0.append(title) } }
}

/// Sparkle as a test sets it: what it can do and how it is set, the checks
/// asked of it, and Sparkle's own windows changing its settings. It never
/// asks the network.
@MainActor
final class FakeUpdater: AppUpdating {
    var canCheckForUpdates = true
    var checksAutomatically = false
    var downloadsAutomatically = false
    var onChange: (@MainActor () -> Void)?
    private(set) var checks = 0

    func checkForUpdates() {
        self.checks += 1
    }

    /// A check starts or ends, and Check for Updates… follows.
    func setCanCheck(_ canCheck: Bool) {
        self.canCheckForUpdates = canCheck
        self.onChange?()
    }

    /// The answer to Sparkle's question on the second launch, or to its
    /// update window's checkbox.
    func answer(checks: Bool, downloads: Bool) {
        self.checksAutomatically = checks
        self.downloadsAutomatically = downloads
        self.onChange?()
    }
}
