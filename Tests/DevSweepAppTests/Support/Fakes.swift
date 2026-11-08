import DevSweepKit
import Foundation
import Synchronization
@testable import DevSweepApp

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

/// The rows as a clean sees them, with no kit behind them. A clean can be
/// asked for and answered, and `cleansBegun` counts the ones that went
/// ahead, but none of them can take the rows, so nothing is cleaned. The
/// flow tests clean for real, on a fake home.
@MainActor
final class FakeScanRows: ScanRows {
    var rows: [Item: ScanRow]
    var isScanning = false
    var isCleaning = false
    private(set) var cleansBegun = 0

    init(_ results: [ItemResult]) {
        self.rows = measuredRows(results)
    }

    var engine: Engine? {
        nil
    }

    func beginCleaning() -> Bool {
        self.cleansBegun += 1
        return false
    }

    // A clean that can't take the rows never gets this far.
    func endCleaning(warnings: [String]) {}
    func diskChanged() {}
    func startCleaning(_ item: Item, kilobytes: Int64?) {}
    func cleaningProgress(_ item: Item, removedBytes: Int64) {}
    func finishCleaning(_ item: Item, outcome: CleanOutcome?) {}
    func finishCleaningParts(_ item: Item, left: ItemResult) {}
    func putBack(_ item: Item) {}
    func putBackParts(_ item: Item, whole: ItemResult) {}

    func tilde(_ path: String) -> String {
        path
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
    private(set) var running: Set<DeveloperApp>
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
