import AppKit
import DevSweepKit
import Observation
import SwiftUI

/// Everything the window shows, fed by the kit's scan events.
@MainActor
@Observable
final class AppModel {
    enum Screen: Hashable {
        case overview
        case xcodeVersions
        case simulatorRuntimes
        case androidStudios
        case androidSDK
        case gradleCaches
        case worktrees
    }

    enum ChartStyle: String, CaseIterable, Identifiable {
        case ring = "Ring"
        case blocks = "Blocks"
        var id: Self {
            self
        }
    }

    var screen: Screen = .overview
    var chartStyle: ChartStyle = .ring
    /// Whether you want the inspector. It shows whenever you do, beside the
    /// center or over it (`inspectorPlacement`).
    var wantsInspector = true
    /// Whether the detail area has room for the inspector beside the center
    /// at its minimum; the window sets it as it resizes.
    var inspectorHasRoom = true
    /// The height of the overview's footer, which a floating inspector stays
    /// above so the footer's buttons stay in reach.
    var overviewFooterHeight: CGFloat = 0
    var selection: Item?
    /// The runtime selected on the runtimes screen, by its simctl id.
    var selectedRuntime: String?
    /// The Xcode selected on the Xcode versions screen, by its path.
    var selectedXcode: String?
    /// The worktree selected on the worktrees screen, by its path.
    var selectedWorktree: String?
    var marked: Set<Item> = []
    /// Parts of items ticked in the inspector, cleaned on their own.
    private(set) var partMarks: [Item: Set<ItemPart>] = [:]
    /// Each item's last parts clean, which the inspector reports and can put
    /// back from the Trash.
    private(set) var partsCleans: [Item: PartsClean] = [:]
    /// Clean by moving to the Trash, so anything can be put back; off deletes for good.
    var moveToTrash = true
    var pendingClean: PendingClean?
    var notice: Notice?
    private(set) var isCleaning = false
    private(set) var trashedThisSession: Int64 = 0
    private(set) var deletedThisSession: Int64 = 0
    private(set) var rows: [Item: Row] = [:]
    private(set) var scanOrder: [Item] = []
    private(set) var isScanning = false
    private(set) var isLoadingExtras = false
    private(set) var isLoadingAndroid = false
    private(set) var lastScan: Date?
    private(set) var diskSpace: DiskSpace?
    /// Installed Xcodes and runtimes. Set by scans; tests set it directly.
    var extras: Extras?
    /// What Android Studio keeps. Set by scans; tests set it directly.
    var android: AndroidReport?
    /// The Android entry selected on its screen, by path.
    var selectedAndroidEntry: String?
    private(set) var projectFolders: ProjectFolders?
    private(set) var warnings: [String] = []
    private(set) var runningApps: Set<DeveloperApp> = []
    let volumeName: String
    /// Rebuilt from the preferences when a scan starts.
    private(set) var engine: Engine?
    private(set) var startupError: String?
    let preferences: Preferences
    let notifier: NotificationPoster
    /// The last growth alert posted, for the menu bar panel.
    private(set) var lastAlert: GrowthCheck.Alert?
    private let environment: [String: String]
    private let dependencies: Dependencies

    /// How long the last scan took, in seconds since it started: until every
    /// item was measured, and until the extras were listed too.
    private(set) var scanTiming: (items: Double, total: Double)?
    private var scanStarted: ContinuousClock.Instant?
    private var itemsDone: Double?
    private var extrasDone: Double?
    private var androidDone: Double?

    /// When the results on screen came from the last launch's scan.
    private(set) var previousScanDate: Date?
    /// Ticks every half minute so "3 minutes ago" stays true.
    private(set) var now = Date()
    private var store: (any ScanMemoryStore)?
    /// Progress that arrived since the screen last showed it.
    private var pendingProgress: [Item: Int64] = [:]
    private var progressFlush: Task<Void, Never>?
    private var marksTouched = false
    private var scanTask: Task<Void, Never>?
    private let workspaceApps: WorkspaceRunningApps
    private let quitter: any AppQuitting

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        store: (any ScanMemoryStore)? = nil,
        preferences: Preferences? = nil,
        notifier: NotificationPoster = UserNotificationPoster(),
        dependencies: Dependencies? = nil,
        quitter: (any AppQuitting)? = nil)
    {
        self.notifier = notifier
        self.quitter = quitter ?? WorkspaceAppQuitter()
        let preferences = preferences ?? Preferences()
        self.preferences = preferences
        let workspaceApps = WorkspaceRunningApps()
        self.workspaceApps = workspaceApps
        // Opened from Finder, the app gets launchd's short PATH, without
        // Homebrew, so Homebrew's usual places go after it. A PATH given on
        // purpose, a terminal's or a test's, is left as it is.
        var environment = environment
        let launchdPath = "/usr/bin:/bin:/usr/sbin:/sbin"
        let path = environment["PATH"] ?? launchdPath
        if path == launchdPath {
            environment["PATH"] = ([path] + ["/opt/homebrew/bin", "/usr/local/bin"]).joined(separator: ":")
        }
        var live = Dependencies.live(environment: environment)
        live.tools.runningApps = workspaceApps
        #if DEBUG
        // Trying the app against a fake home shouldn't fill the real Trash.
        if let folder = environment["DEVSWEEP_TRASH_FOLDER"] {
            live.tools.trash = FolderTrash(folder: folder)
        }
        #endif
        let dependencies = dependencies ?? live
        self.environment = environment
        self.dependencies = dependencies
        self.moveToTrash = preferences.moveToTrash
        (self.engine, self.startupError) = Self.makeEngine(
            preferences: preferences,
            environment: environment,
            dependencies: dependencies)
        self.volumeName = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]))?
            .volumeLocalizedName ?? "Macintosh HD"
        self.rows = Dictionary(uniqueKeysWithValues: (self.engine?.items ?? []).map { ($0, Row(item: $0)) })
        self.scanOrder = self.engine?.items ?? []
        self.diskSpace = self.engine?.diskSpace()
        self.store = store ?? self.engine.map { ScanStore.standard(home: $0.config.home) }
        self.restorePreviousScan()
        workspaceApps.onChange = { [weak self] in
            Task { await self?.refreshRunningApps() }
        }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.tick(now: Date())
            }
        }
    }

    /// Every half minute: the clock for "3 minutes ago", the free space for
    /// the menu bar, and a scan once the last one is a day old.
    func tick(now: Date) {
        self.now = now
        self.diskSpace = self.engine?.diskSpace() ?? self.diskSpace
        if ScanSchedule.isDue(lastScan: self.lastScan, now: now), !self.isScanning, !self.isCleaning {
            self.scan()
        }
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

    // MARK: Scanning

    func scan() {
        guard !self.isScanning, !self.isCleaning else { return }
        // Preferences changed since the last scan apply from this one.
        (engine, self.startupError) = Self.makeEngine(
            preferences: self.preferences,
            environment: self.environment,
            dependencies: self.dependencies)
        guard let engine else { return }
        // What was on screen becomes the dimmed "last scan" until replaced.
        self.rows = Dictionary(uniqueKeysWithValues: engine.items.map { item in
            var row = Row(item: item)
            row.previous = self.rows[item]?.result ?? self.rows[item]?.previous
            return (item, row)
        })
        if self.lastScan != nil { self.previousScanDate = self.lastScan }
        self.scanOrder = engine.items
        self.warnings = []
        self.marksTouched = false
        self.marked = []
        self.partMarks = [:]
        self.partsCleans = [:]
        self.isScanning = true
        self.isLoadingExtras = engine.config.includeExtras
        self.isLoadingAndroid = engine.config.includeAndroid
        self.scanStarted = .now
        self.itemsDone = nil
        self.extrasDone = nil
        self.androidDone = nil
        self.scanTiming = nil

        self.scanTask = Task {
            await self.refreshRunningApps()
            for await event in engine.scan(.interactive) {
                self.apply(event)
            }
            self.flushProgress()
            self.finishScan()
            self.scanTask = nil
        }
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

    func stopScan() {
        self.scanTask?.cancel()
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
            self.applyDefaultMarks()
            if self.selection == nil { self.selection = self.orderedRows.first?.item }
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
            rows[item]?.progressBytes = bytes
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
        if let alert = GrowthCheck.derivedData(
            previousKilobytes: rows[.derivedData]?.previous?.kilobytes,
            currentKilobytes: rows[.derivedData]?.result?.kilobytes,
            thresholdGigabytes: preferences.derivedDataGrowthGigabytes)
        {
            self.lastAlert = alert
            let notifier = notifier
            Task { await notifier.post(title: alert.title, body: alert.body) }
        }
    }

    private func finishScan() {
        self.isLoadingExtras = false
        self.isLoadingAndroid = false
        guard self.isScanning else { return }
        // Stopped before the end: what wasn't reached stays unmeasured.
        withAnimation(Motion.animation()) {
            for item in self.scanOrder where !(self.rows[item]?.wasMeasured ?? false) {
                rows[item]?.state = .notMeasured
                rows[item]?.progressBytes = 0
            }
            self.isScanning = false
        }
        self.lastScan = Date()
        self.diskSpace = self.engine?.diskSpace()
        self.applyDefaultMarks()
    }

    /// The three biggest items start marked, unless marks were changed during the scan.
    private func applyDefaultMarks() {
        guard !self.marksTouched else { return }
        self.marked = Set(self.liveRows.prefix(3).map(\.item))
    }

    func refreshRunningApps() async {
        var running = Set<DeveloperApp>()
        // The live dependencies ask the workspace; tests say what runs.
        for app in DeveloperApp.allCases where await self.dependencies.tools.runningApps.isRunning(app) {
            running.insert(app)
        }
        self.runningApps = running
    }

    // MARK: Marks and selection

    func setMarked(_ item: Item, _ isMarked: Bool) {
        self.marksTouched = true
        if isMarked { self.marked.insert(item) } else { self.marked.remove(item) }
    }

    func markAll() {
        self.marksTouched = true
        self.marked = Set(self.liveRows.map(\.item))
    }

    func markNone() {
        self.marksTouched = true
        self.marked = []
    }

    /// Selects the biggest item of a family on the overview.
    func pick(_ family: Family) {
        self.screen = .overview
        if let biggest = liveRows.first(where: { $0.item.family == family }) ?? orderedRows
            .first(where: { $0.item.family == family })
        {
            self.selection = biggest.item
        }
    }

    // MARK: Derived values

    /// The rows' order, totals and weights.
    var tally: Tally {
        Tally(order: self.scanOrder, rows: self.rows)
    }

    var orderedRows: [Row] {
        self.tally.ordered
    }

    var liveRows: [Row] {
        self.tally.live
    }

    var markedRows: [Row] {
        self.tally.marked(self.marked)
    }

    var reclaimableKilobytes: Int64 {
        self.tally.reclaimableKilobytes
    }

    var markedKilobytes: Int64 {
        self.tally.markedKilobytes(self.marked)
    }

    func measuredKilobytes(of family: Family) -> Int64? {
        self.tally.measuredKilobytes(of: family)
    }

    func familyShowsPrevious(_ family: Family) -> Bool {
        self.tally.familyShowsPrevious(family)
    }

    var showsPrevious: Bool {
        self.tally.showsPrevious
    }

    var measuredCount: Int {
        self.tally.measuredCount
    }

    var measuringItems: [Item] {
        self.tally.measuringItems
    }

    func chartWeight(_ row: Row) -> Double {
        self.tally.chartWeight(row)
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

    var statusLine: String {
        StatusText.overview(
            self.statusFacts,
            runningApps: self.runningApps,
            trashedKilobytes: self.trashedThisSession,
            deletedKilobytes: self.deletedThisSession)
    }

    var runningAppsSentence: String {
        StatusText.runningApps(self.runningApps)
    }

    func tilde(_ path: String) -> String {
        self.engine?.policy.tilde(path) ?? path
    }

    /// Shows results as if a scan had just measured them, without scanning.
    /// For tests.
    func showResults(_ results: [ItemResult]) {
        for result in results {
            self.rows[result.item]?.result = result
            self.rows[result.item]?.state = .measured
        }
        self.lastScan = Date()
        self.selection = self.orderedRows.first?.item
    }

    /// Where the inspector shows.
    enum InspectorPlacement: String {
        /// In its own panel beside the center, when the window has room.
        case docked
        /// Over the center's trailing side, when the window is too narrow
        /// for it beside the center: still there to read, and to hide.
        case floating
        case hidden
    }

    var inspectorPlacement: InspectorPlacement {
        guard self.wantsInspector else { return .hidden }
        return self.inspectorHasRoom ? .docked : .floating
    }

    var inspectorShown: Bool {
        self.inspectorPlacement != .hidden
    }

    /// What the inspector's toggle and the View menu do: show or hide it. In
    /// a window too narrow for it beside the center, it floats over it; the
    /// window keeps its size.
    func toggleInspector() {
        self.wantsInspector.toggle()
    }

    /// Shows the overview with `style`, as the View menu's Ring and Blocks do.
    func showChart(_ style: ChartStyle) {
        self.screen = .overview
        self.chartStyle = style
    }

    #if DEBUG
    /// Puts the model back to the moment `measured` items were done, for snapshots.
    func rewindScan(toMeasured measured: Int) {
        for (index, item) in self.scanOrder.enumerated() where index >= measured {
            guard var row = rows[item] else { continue }
            row.previous = row.result
            row.progressBytes = index == measured ? row.kilobytes * 1024 / 3 : 0
            row.state = index == measured ? .measuring : .waiting
            row.result = nil
            rows[item] = row
        }
        self.isScanning = true
        self.marked = []
    }
    #endif

    // MARK: Cleaning

    /// Starts cleaning `items`: asks to quit Xcode and Simulator when an Xcode
    /// item needs them closed, and asks to confirm anything that can't be put back.
    func requestClean(_ items: [Item]) async {
        guard !self.isScanning, !self.isCleaning else { return }
        let items = items.filter { self.rows[$0]?.isLive ?? false }
        guard !items.isEmpty else { return }
        await self.refreshRunningApps()
        let blocking = DeveloperApp.allCases.filter(self.runningApps.contains)
        if items.contains(where: \.needsXcodeClosed), !blocking.isEmpty {
            self.pendingClean = PendingClean(items: items, stage: .quitApps(blocking))
        } else {
            self.confirmOrClean(items)
        }
    }

    /// Quits Xcode and Simulator, then goes on with the clean.
    func quitAppsAndClean(_ pending: PendingClean) async {
        self.pendingClean = nil
        guard case let .quitApps(apps) = pending.stage else { return }
        if await self.quit(apps) {
            self.confirmOrClean(pending.items, parts: pending.parts, afterAlert: true)
        } else {
            self.notice = Notice(
                title: "\(apps.map(\.rawValue).joined(separator: " and ")) didn't quit",
                message: "Nothing was cleaned. Quit them yourself, for example after saving your work, and clean "
                    + "again.")
        }
    }

    /// Goes on with the items, or the parts, that don't need Xcode closed.
    func cleanSkippingXcodeItems(_ pending: PendingClean) {
        self.pendingClean = nil
        if let item = pending.items.first, !pending.parts.isEmpty {
            let rest = pending.parts.filter { !$0.needsXcodeClosed(in: item) }
            if !rest.isEmpty { self.confirmOrClean(pending.items, parts: rest, afterAlert: true) }
            return
        }
        let rest = pending.items.filter { !$0.needsXcodeClosed }
        if !rest.isEmpty { self.confirmOrClean(rest, afterAlert: true) }
    }

    func confirmClean(_ pending: PendingClean) async {
        self.pendingClean = nil
        if let item = pending.items.first, !pending.parts.isEmpty {
            await self.performClean(pending.parts, of: item)
        } else {
            await self.performClean(pending.items)
        }
    }

    /// Whether these items need a yes first: everything does when deleting
    /// for good, and Simulators and Homebrew always, since their tools delete
    /// them. Parts of what Xcode builds into do while Xcode is open, which
    /// may have the project open.
    func needsConfirmation(_ items: [Item], parts: Set<ItemPart> = []) -> Bool {
        !self.moveToTrash || items.contains(where: \.cleanedByItsTool)
            || (!parts.isEmpty && self.runningApps.contains(.xcode) && items.contains(where: \.xcodeBuildsInto))
    }

    /// - Parameter afterAlert: an alert is closing, so give it a moment
    ///   before showing the next one.
    private func confirmOrClean(_ items: [Item], parts: Set<ItemPart> = [], afterAlert: Bool = false) {
        if self.needsConfirmation(items, parts: parts) {
            Task {
                if afterAlert { try? await Task.sleep(for: .milliseconds(300)) }
                if let item = items.first, !parts.isEmpty {
                    self.pendingClean = self.partsQuestion(parts, of: item, stage: .confirm)
                } else {
                    self.pendingClean = PendingClean(items: items, stage: .confirm)
                }
            }
        } else if let item = items.first, !parts.isEmpty {
            Task { await self.performClean(parts, of: item) }
        } else {
            Task { await self.performClean(items) }
        }
    }

    private func performClean(_ items: [Item]) async {
        guard let engine, !isCleaning else { return }
        self.isCleaning = true
        let mode: CleanMode = self.moveToTrash ? .trash : .delete
        var problems: [String] = []

        for item in items {
            guard let row = rows[item], row.isLive, let result = row.result else { continue }
            // Xcode may have been opened since the question was asked.
            if item.needsXcodeClosed {
                await self.refreshRunningApps()
                if !self.runningApps.isEmpty {
                    problems.append("Skipped \(item.name): \(self.runningAppsSentence)")
                    continue
                }
            }
            withAnimation(Motion.animation()) { self.rows[item]?.state = .cleaning }
            let outcome = await self.countingDown(item) { await engine.clean(result, mode: mode, progress: $0) }
            problems += outcome.warnings
            let removedSomething = !outcome.removed.isEmpty || outcome.toolSucceeded == true
            withAnimation(Motion.animation(.easeInOut(duration: 0.4))) {
                if removedSomething {
                    self.rows[item]?.state = .cleaned
                    self.rows[item]?.outcome = outcome
                    self.marked.remove(item)
                    // What a parts clean put in the Trash went with the rest.
                    self.partsCleans[item] = nil
                    if outcome.canPutBack {
                        self.trashedThisSession += result.kilobytes
                    } else {
                        self.deletedThisSession += result.kilobytes
                    }
                } else {
                    self.rows[item]?.state = .measured
                }
            }
        }

        self.isCleaning = false
        self.diskSpace = engine.diskSpace()
        self.saveScan()
        self.warnings += problems
        if !problems.isEmpty {
            self.notice = Notice(title: "Some things were left alone", message: problems.joined(separator: "\n"))
        }
    }

    /// Runs a clean with `item`'s row counting down as it reports. The
    /// removal reports from several threads; the row shows the latest count
    /// about ten times a second.
    private func countingDown<Outcome>(
        _ item: Item,
        _ clean: (@escaping @Sendable (Int64) -> Void) async -> Outcome) async -> Outcome
    {
        let (removed, reporter) = AsyncStream.makeStream(of: Int64.self, bufferingPolicy: .bufferingNewest(1))
        let counter = Task {
            for await bytes in removed {
                self.rows[item]?.removedBytes = bytes
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        let outcome = await clean { reporter.yield($0) }
        reporter.finish()
        counter.cancel()
        self.rows[item]?.removedBytes = 0
        return outcome
    }

    /// Moves what cleaning `item` put in the Trash back where it was.
    func putBack(_ item: Item) async {
        guard let engine, let row = rows[item], row.canPutBack, let outcome = row.outcome else { return }
        let result = await engine.putBack(outcome)
        withAnimation(Motion.animation(.easeInOut(duration: 0.4))) {
            if !result.restored.isEmpty {
                self.rows[item]?.state = .measured
                self.rows[item]?.outcome = nil
                self.trashedThisSession = max(0, self.trashedThisSession - row.kilobytes)
            }
        }
        self.diskSpace = engine.diskSpace()
        self.saveScan()
        self.reportPutBackFailures(result.failed)
    }

    private func reportPutBackFailures(_ failed: [String]) {
        guard !failed.isEmpty else { return }
        self.notice = Notice(
            title: "Some folders couldn't be put back",
            message: "Something now stands where they were, or the folder that held them changed. They are still "
                + "in the Trash:\n"
                + failed.map(self.tilde).joined(separator: "\n"))
    }

    // MARK: Xcodes and runtimes

    /// The runtime waiting on the removal sheet.
    var runtimeToRemove: SimulatorRuntime?
    private(set) var isRemovingRuntime = false
    var runtimeRemovalError: String?

    var staleDays: Int {
        self.preferences.staleDays
    }

    /// The selected runtime, or the first flagged one, or the first.
    var currentRuntime: SimulatorRuntime? {
        let runtimes = self.extras?.runtimes ?? []
        return runtimes.first { $0.id == self.selectedRuntime }
            ?? runtimes.first { $0.flagReason(staleDays: self.staleDays) != nil }
            ?? runtimes.first
    }

    /// What the current Android screen lists, in the order it shows them.
    var androidEntries: [AndroidEntry] {
        guard let android else { return [] }
        switch self.screen {
        case .androidStudios: return android.studios
        case .androidSDK: return android.emulators + android.systemImages + android.platforms + android
            .buildTools + android.otherSDKParts
        case .gradleCaches: return android.gradleCaches
        default: return []
        }
    }

    /// The selected Android entry on this screen, or the first flagged one, or the first.
    var currentAndroidEntry: AndroidEntry? {
        let entries = self.androidEntries
        return entries.first { $0.path == self.selectedAndroidEntry }
            ?? entries.first { $0.flagReason(staleDays: self.staleDays) != nil }
            ?? entries.first
    }

    var currentXcode: InstalledXcode? {
        let xcodes = self.extras?.xcodes ?? []
        return xcodes.first { $0.path == self.selectedXcode } ?? xcodes.first { $0.isSelected } ?? xcodes.first
    }

    /// The subtitle under each screen's title.
    var subtitle: String {
        switch self.screen {
        case .overview:
            // A development build says what it was built from, so an old
            // bundle can't pass for the latest.
            [self.statusLine, BuildIdentity.current.statusNote].compactMap(\.self).joined(separator: " ")
        case .simulatorRuntimes: StatusText.runtimes(self.extras?.runtimes, isLoading: self.isLoadingExtras)
        case .xcodeVersions: StatusText.xcodes(self.extras?.xcodes, isLoading: self.isLoadingExtras)
        case .androidStudios: StatusText.androidStudios(self.android, isLoading: self.isLoadingAndroid)
        case .androidSDK: StatusText.androidSDK(self.android, isLoading: self.isLoadingAndroid)
        case .gradleCaches: StatusText.gradleCaches(self.android, isLoading: self.isLoadingAndroid)
        case .worktrees: StatusText.worktrees(self.extras?.worktrees, isLoading: self.isLoadingExtras)
        }
    }

    /// Removes the runtime on the sheet through simctl, then lists runtimes again.
    func removeRuntime(_ runtime: SimulatorRuntime) async {
        guard let engine, !isRemovingRuntime else { return }
        self.isRemovingRuntime = true
        self.runtimeRemovalError = nil
        let removed = await engine.removeRuntime(runtime)
        self.isRemovingRuntime = false
        if removed {
            self.runtimeToRemove = nil
            self.selectedRuntime = nil
            await self.refreshExtras()
            self.diskSpace = engine.diskSpace()
        } else {
            self.runtimeRemovalError = "simctl couldn't remove it. Run the command in Terminal to see why; "
                + "a simulator using it may still be running."
        }
    }

    /// The worktree waiting on the removal sheet.
    var worktreeToRemove: GitWorktree?
    private(set) var isRemovingWorktree = false
    var worktreeRemovalError: String?

    /// Removes the worktree on the sheet with git, then lists worktrees again.
    func removeWorktree(_ worktree: GitWorktree) async {
        guard let engine, !isRemovingWorktree else { return }
        self.isRemovingWorktree = true
        self.worktreeRemovalError = nil
        let removed = await engine.removeWorktree(worktree)
        self.isRemovingWorktree = false
        if removed {
            self.worktreeToRemove = nil
            self.selectedWorktree = nil
            await self.refreshExtras()
            self.diskSpace = engine.diskSpace()
        } else {
            self.worktreeRemovalError = "Git didn't remove it. It may have changed since it was listed, or hold a "
                + "submodule; run the command in Terminal to see why."
        }
    }

    func refreshExtras() async {
        guard let engine else { return }
        self.isLoadingExtras = true
        let fresh = await engine.extras()
        withAnimation(Motion.animation()) { self.extras = fresh }
        self.isLoadingExtras = false
    }

    /// Asks the apps to quit and waits for them.
    private func quit(_ apps: [DeveloperApp]) async -> Bool {
        let quit = await self.quitter.quit(apps)
        await self.refreshRunningApps()
        return quit
    }

    // MARK: Finder

    func revealInFinder(_ paths: [String]) {
        let urls = paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

/// The questions a clean waits on, and what the window says after.
extension AppModel {
    /// A clean waiting on an answer: quit Xcode first, or confirm.
    struct PendingClean: Identifiable {
        enum Stage {
            case quitApps([DeveloperApp])
            case confirm
        }

        let id = UUID()
        let items: [Item]
        let stage: Stage
        /// Parts of the item to clean instead of the whole of it.
        var parts: Set<ItemPart> = []
        /// What the question calls those parts: "DerivedData for Atlas",
        /// "kite-1/.build and kite-2/.build", "5 .build folders".
        var partsSubject = ""
        /// Whether that subject takes "go" rather than "goes".
        var partsPlural = false
        /// Those of them that need Xcode closed, by name.
        var blockedPartNames: [String] = []
        /// Asked while Xcode is open, which may have the project open.
        var xcodeOpen = false
        /// The project to close in Xcode, for one part; empty for several.
        var xcodeName = ""

        /// Whether some of it can be cleaned with Xcode and Simulator open.
        var hasOthers: Bool {
            guard let item = self.items.first, !self.parts.isEmpty else {
                return self.items.contains { !$0.needsXcodeClosed }
            }
            return self.parts.contains { !$0.needsXcodeClosed(in: item) }
        }
    }

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }
}

// MARK: Cleaning parts of an item

extension AppModel {
    /// A clean of some parts of an item, which the inspector reports.
    struct PartsClean {
        let outcome: PartsCleanOutcome
        /// The item's result before, to put parts back as they were measured.
        let before: ItemResult
        /// What it took from the item's size.
        let kilobytes: Int64
        /// "2 projects", "3 folders".
        let summary: String

        var canPutBack: Bool {
            self.outcome.outcome.canPutBack
        }
    }

    /// The question about cleaning `parts` of `item`.
    func partsQuestion(_ parts: Set<ItemPart>, of item: Item, stage: PendingClean.Stage) -> PendingClean {
        CleanPrompt.partsQuestion(
            parts,
            of: item,
            in: self.rows[item]?.result,
            xcodeOpen: self.runningApps.contains(.xcode),
            stage: stage)
    }

    func markedParts(of item: Item) -> Set<ItemPart> {
        self.partMarks[item] ?? []
    }

    func lastPartsClean(of item: Item) -> PartsClean? {
        self.partsCleans[item]
    }

    func setMarked(_ part: ItemPart, of item: Item, _ marked: Bool) {
        if marked {
            self.partMarks[item, default: []].insert(part)
        } else {
            self.partMarks[item]?.remove(part)
        }
    }

    func kilobytes(of parts: Set<ItemPart>, in item: Item) -> Int64 {
        guard let result = self.rows[item]?.result else { return 0 }
        return parts.reduce(0) { $0 + result.kilobytes(of: $1) }
    }

    /// Starts cleaning the ticked parts of `item`. Parts that need Xcode
    /// closed ask to quit it and Simulator, as the whole item does; the rest
    /// can go while Xcode is open, after a question when Xcode builds into
    /// the item, since it may have the project open.
    func requestCleanParts(of item: Item) async {
        guard !self.isScanning, !self.isCleaning, self.rows[item]?.isLive == true else { return }
        let parts = self.markedParts(of: item)
        guard !parts.isEmpty else { return }
        await self.refreshRunningApps()
        let blocking = DeveloperApp.allCases.filter(self.runningApps.contains)
        if parts.contains(where: { $0.needsXcodeClosed(in: item) }), !blocking.isEmpty {
            self.pendingClean = self.partsQuestion(parts, of: item, stage: .quitApps(blocking))
        } else {
            self.confirmOrClean([item], parts: parts)
        }
    }

    func performClean(_ parts: Set<ItemPart>, of item: Item) async {
        guard let engine, !self.isCleaning, let row = self.rows[item], row.isLive, let result = row.result
        else { return }
        // Xcode may have been opened since the question was asked.
        if parts.contains(where: { $0.needsXcodeClosed(in: item) }) {
            await self.refreshRunningApps()
            if !self.runningApps.isEmpty {
                self.notice = Notice(title: "Nothing was cleaned", message: self.runningAppsSentence)
                return
            }
        }
        self.isCleaning = true
        let mode: CleanMode = self.moveToTrash ? .trash : .delete
        withAnimation(Motion.animation()) {
            self.rows[item]?.state = .cleaning
            self.rows[item]?.cleaningKilobytes = parts.reduce(0) { $0 + result.kilobytes(of: $1) }
        }
        let outcome = await self.countingDown(item) {
            await engine.clean(parts, of: result, mode: mode, progress: $0)
        }
        let cleaned = outcome.cleaned
        let left = result.removing(cleaned)
        let freed = result.kilobytes - left.kilobytes
        withAnimation(Motion.animation(.easeInOut(duration: 0.4))) {
            self.rows[item]?.result = left
            self.rows[item]?.state = .measured
            self.rows[item]?.cleaningKilobytes = nil
            self.partMarks[item]?.subtract(cleaned)
        }
        if !cleaned.isEmpty {
            if outcome.outcome.canPutBack {
                self.trashedThisSession += freed
            } else {
                self.deletedThisSession += freed
            }
            self.partsCleans[item] = PartsClean(
                outcome: outcome,
                before: result,
                kilobytes: freed,
                summary: CleanPrompt.partsSummary(cleaned, in: item))
        }
        self.isCleaning = false
        self.diskSpace = engine.diskSpace()
        self.saveScan()
        let problems = outcome.outcome.warnings
        self.warnings += problems
        if !problems.isEmpty {
            self.notice = Notice(title: "Some things were left alone", message: problems.joined(separator: "\n"))
        }
    }

    /// Moves what the last parts clean of `item` put in the Trash back where it was.
    func putBackParts(of item: Item) async {
        guard let engine, !self.isCleaning, let clean = self.partsCleans[item], clean.canPutBack,
              let result = self.rows[item]?.result
        else { return }
        let putBack = await engine.putBack(clean.outcome.outcome)
        let restored = clean.outcome.restored(by: putBack)
        let whole = result.restoring(restored, from: clean.before)
        withAnimation(Motion.animation(.easeInOut(duration: 0.4))) {
            self.rows[item]?.result = whole
        }
        self.trashedThisSession = max(0, self.trashedThisSession - (whole.kilobytes - result.kilobytes))
        self.partsCleans[item] = nil
        self.diskSpace = engine.diskSpace()
        self.saveScan()
        self.reportPutBackFailures(putBack.failed)
    }
}
