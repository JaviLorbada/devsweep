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

    /// A clean waiting on an answer: quit Xcode first, or confirm.
    struct PendingClean: Identifiable {
        enum Stage {
            case quitApps([DeveloperApp])
            case confirm
        }

        let id = UUID()
        let items: [Item]
        let stage: Stage
        /// Parts of DerivedData to clean instead of the whole of it.
        var parts: Set<DerivedDataPart> = []
        /// What the question calls those parts, largest first.
        var partNames: [String] = []
        /// Those of them that need Xcode closed, by name.
        var blockedPartNames: [String] = []
        /// Asked about projects while Xcode is open, which may have one of them open.
        var xcodeOpen = false

        /// Whether some of it can be cleaned with Xcode and Simulator open.
        var hasOthers: Bool {
            self.parts.isEmpty
                ? self.items.contains { !$0.needsXcodeClosed }
                : self.parts.contains { !$0.needsXcodeClosed }
        }
    }

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
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
    /// The DerivedData parts ticked in the inspector, cleaned on their own.
    var markedParts: Set<DerivedDataPart> = []
    /// The last clean of DerivedData parts, which the inspector reports and
    /// can put back from the Trash.
    private(set) var lastPartsClean: PartsClean?
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

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        store: (any ScanMemoryStore)? = nil,
        preferences: Preferences? = nil,
        notifier: NotificationPoster = UserNotificationPoster(),
        dependencies: Dependencies? = nil)
    {
        self.notifier = notifier
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
        self.markedParts = []
        self.lastPartsClean = nil
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

    /// Measured items largest first, then the ones being measured, then the
    /// rest; those two by what the last scan found, so rows keep their places.
    var orderedRows: [Row] {
        let all = self.scanOrder.compactMap { self.rows[$0] }
        let byPrevious = { (a: Row, b: Row) in (a.previous?.kilobytes ?? 0) > (b.previous?.kilobytes ?? 0) }
        let measured = all.filter(\.wasMeasured).sorted { $0.kilobytes > $1.kilobytes }
        return measured + all.filter { $0.state == .measuring }.sorted(by: byPrevious)
            + all.filter { $0.state == .waiting || $0.state == .notMeasured }.sorted(by: byPrevious)
    }

    var liveRows: [Row] {
        self.orderedRows.filter(\.isLive)
    }

    var markedRows: [Row] {
        self.liveRows.filter { self.marked.contains($0.item) }
    }

    /// Rows whose size counts toward the totals on screen: measured with
    /// something to reclaim, counting up, or still showing the last scan.
    private var countedRows: [Row] {
        self.orderedRows.filter { $0.isLive || $0.isCounting || $0.showsPrevious }
    }

    /// The total on screen: this scan's sizes where it has them, the running
    /// counts, and the last scan's sizes for what it hasn't reached yet.
    var reclaimableKilobytes: Int64 {
        self.countedRows.reduce(0) { $0 + $1.shownKilobytes }
    }

    var markedKilobytes: Int64 {
        self.markedRows.reduce(0) { $0 + $1.kilobytes }
    }

    func kilobytes(of family: Family) -> Int64 {
        self.countedRows.filter { $0.item.family == family }.reduce(0) { $0 + $1.shownKilobytes }
    }

    /// What each family takes of the legend's bar: the sum of its items'
    /// shares, with small items drawn larger (`ChartScale`), as the ring's
    /// inner circle draws it once the scan is done.
    var familyChartShares: [Family: Double] {
        let rows = self.countedRows
        let shares = ChartScale.shares(rows.map { Double($0.shownKilobytes) })
        return zip(rows, shares).reduce(into: [:]) { $0[$1.0.item.family, default: 0] += $1.1 }
    }

    /// The family's size once anything is known about it, nil before.
    func measuredKilobytes(of family: Family) -> Int64? {
        let known = family.items.contains { item in
            guard let row = rows[item] else { return false }
            return row.wasMeasured || row.isCounting || row.showsPrevious
        }
        return known ? self.kilobytes(of: family) : nil
    }

    /// Whether everything shown for the family comes from the last scan.
    func familyShowsPrevious(_ family: Family) -> Bool {
        let rows = family.items.compactMap { self.rows[$0] }
        return rows.contains(where: \.showsPrevious) && !rows.contains { $0.wasMeasured || $0.isCounting }
    }

    /// Whether the totals still lean on the last scan.
    var showsPrevious: Bool {
        self.scanOrder.contains { self.rows[$0]?.showsPrevious ?? false }
    }

    var measuredCount: Int {
        self.scanOrder.filter { self.rows[$0]?.wasMeasured ?? false }.count
    }

    var measuringItems: [Item] {
        self.scanOrder.filter { self.rows[$0]?.state == .measuring }
    }

    var currentItem: Item? {
        self.measuringItems.first
    }

    var scanProgress: Double {
        self.scanOrder.isEmpty ? 0 : Double(self.measuredCount) / Double(self.scanOrder.count)
    }

    /// The weight a ring segment gets: its size once measured, otherwise what
    /// it took last time or the average so far, so the ring is whole from the start.
    func chartWeight(_ row: Row) -> Double {
        switch row.state {
        case .measured, .cleaning, .cleaned:
            return Double(max(row.kilobytes, 0))
        case .notMeasured:
            return 0
        case .measuring where row.progressBytes > 0:
            return Double(row.progressBytes / 1024)
        case .waiting, .measuring:
            if let previous = row.previous { return Double(max(previous.kilobytes, 1)) }
            let measured = self.scanOrder.compactMap { self.rows[$0] }.filter(\.wasMeasured)
            let total = measured.reduce(0) { $0 + Double($1.kilobytes) }
            return measured.isEmpty || total == 0 ? 1 : total / Double(measured.count)
        }
    }

    var statusLine: String {
        if let startupError { return startupError }
        if self.isScanning {
            let progress = "Scanning, \(measuredCount) of \(scanOrder.count) items measured"
            if let previousScanDate, showsPrevious {
                return "Last scanned \(Self.relative(previousScanDate, to: self.now)). \(progress)."
            }
            // Full stops throughout: the build note can follow.
            return "\(progress)."
        }
        guard let lastScan else {
            return self.previousScanDate
                .map { "Last scanned \(Self.relative($0, to: self.now))." } ?? "Not scanned yet."
        }
        let unmeasured = self.scanOrder.filter { self.rows[$0]?.state == .notMeasured }.count
        let scanned = unmeasured > 0
            ? "Stopped after \(measuredCount) of \(scanOrder.count) items."
            : "Scanned \(Self.relative(lastScan, to: self.now)), \(self.scanOrder.count) items."
        var line = "\(scanned) \(runningAppsSentence)"
        if self.trashedThisSession > 0 {
            line += " \(SizeText.of(kilobytes: self.trashedThisSession)) moved to Trash this session."
        }
        if self.deletedThisSession > 0 {
            line += " \(SizeText.of(kilobytes: self.deletedThisSession)) deleted this session."
        }
        return line
    }

    /// "just now", "3 minutes ago", "yesterday".
    static func relative(_ date: Date, to now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    var runningAppsSentence: String {
        switch (self.runningApps.contains(.xcode), self.runningApps.contains(.simulator)) {
        case (false, false): "Xcode and Simulator are closed."
        case (true, false): "Xcode is open."
        case (false, true): "Simulator is open."
        case (true, true): "Xcode and Simulator are open."
        }
    }

    var xcodesKilobytes: Int64? {
        self.extras.map { $0.xcodes.reduce(0) { $0 + $1.kilobytes } }
    }

    var androidStudiosKilobytes: Int64? {
        self.android.map { self.total($0.studios) }
    }

    var androidSDKKilobytes: Int64? {
        self.android.map { self.total($0.sdkEntries + $0.emulators) }
    }

    var gradleCachesKilobytes: Int64? {
        self.android.map { self.total($0.gradleCaches) }
    }

    private func total(_ entries: [AndroidEntry]) -> Int64 {
        entries.reduce(0) { $0 + $1.kilobytes }
    }

    var runtimesKilobytes: Int64? {
        self.extras.map { $0.runtimes.reduce(0) { $0 + $1.kilobytes } }
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
        if !pending.parts.isEmpty {
            let rest = pending.parts.filter { !$0.needsXcodeClosed }
            if !rest.isEmpty { self.confirmOrClean(pending.items, parts: rest, afterAlert: true) }
            return
        }
        let rest = pending.items.filter { !$0.needsXcodeClosed }
        if !rest.isEmpty { self.confirmOrClean(rest, afterAlert: true) }
    }

    func confirmClean(_ pending: PendingClean) async {
        self.pendingClean = nil
        if pending.parts.isEmpty {
            await self.performClean(pending.items)
        } else {
            await self.performClean(pending.parts)
        }
    }

    /// Whether these items need a yes first: everything does when deleting
    /// for good, and Simulators and Homebrew always, since their tools delete
    /// them. Parts of DerivedData do while Xcode is open, which may have one
    /// of the projects open.
    func needsConfirmation(_ items: [Item], parts: Set<DerivedDataPart> = []) -> Bool {
        !self.moveToTrash || items.contains(where: \.cleanedByItsTool)
            || (!parts.isEmpty && self.runningApps.contains(.xcode))
    }

    /// - Parameter afterAlert: an alert is closing, so give it a moment
    ///   before showing the next one.
    private func confirmOrClean(_ items: [Item], parts: Set<DerivedDataPart> = [], afterAlert: Bool = false) {
        if self.needsConfirmation(items, parts: parts) {
            Task {
                if afterAlert { try? await Task.sleep(for: .milliseconds(300)) }
                self.pendingClean = PendingClean(
                    items: items,
                    stage: .confirm,
                    parts: parts,
                    partNames: self.names(of: parts),
                    xcodeOpen: !parts.isEmpty && self.runningApps.contains(.xcode))
            }
        } else if parts.isEmpty {
            Task { await self.performClean(items) }
        } else {
            Task { await self.performClean(parts) }
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
                    // What a parts clean put in the Trash went with the folder.
                    if item == .derivedData { self.lastPartsClean = nil }
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
            return [self.statusLine, BuildIdentity.current.statusNote].compactMap(\.self).joined(separator: " ")
        case .simulatorRuntimes:
            guard let runtimes = extras?.runtimes else { return self.isLoadingExtras ? "Listing runtimes" : "" }
            let count = runtimes.count == 1 ? "1 runtime" : "\(runtimes.count) runtimes"
            return "\(SizeText.of(kilobytes: self.runtimesKilobytes ?? 0)) in \(count). \(ProductInfo.name) never "
                + "removes these on its own."
        case .xcodeVersions:
            guard let xcodes = extras?.xcodes else { return self.isLoadingExtras ? "Listing Xcodes" : "" }
            let count = xcodes.count == 1 ? "1 Xcode" : "\(xcodes.count) Xcodes"
            return "\(SizeText.of(kilobytes: self.xcodesKilobytes ?? 0)) in \(count). \(ProductInfo.name) never "
                + "removes these."
        case .androidStudios:
            guard let studios = android?.studios else { return self.isLoadingAndroid ? "Listing Android Studio" : "" }
            let count = studios.count == 1 ? "1 install" : "\(studios.count) installs"
            return "\(SizeText.of(kilobytes: self.androidStudiosKilobytes ?? 0)) in \(count). \(ProductInfo.name) "
                + "never removes these."
        case .androidSDK:
            guard self.android != nil else { return self.isLoadingAndroid ? "Listing the SDK and emulators" : "" }
            return "\(SizeText.of(kilobytes: self.androidSDKKilobytes ?? 0)) in the SDK and emulators. "
                + "\(ProductInfo.name) never removes these."
        case .gradleCaches:
            guard self.android != nil else { return self.isLoadingAndroid ? "Listing Gradle's caches" : "" }
            return "\(SizeText.of(kilobytes: self.gradleCachesKilobytes ?? 0)) in ~/.gradle. \(ProductInfo.name) "
                + "never removes these."
        case .worktrees:
            guard let worktrees = extras?.worktrees else { return self.isLoadingExtras ? "Listing worktrees" : "" }
            return WorktreeWords.summary(worktrees)
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

    /// Asks the apps to quit, as choosing Quit would, and waits up to 15 seconds.
    private func quit(_ apps: [DeveloperApp]) async -> Bool {
        let running = apps
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleIdentifier) }
        running.forEach { $0.terminate() }
        for _ in 0..<60 {
            if running.allSatisfy(\.isTerminated) { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        await self.refreshRunningApps()
        return running.allSatisfy(\.isTerminated)
    }

    // MARK: Finder

    func revealInFinder(_ paths: [String]) {
        let urls = paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

/// The rows, one per item, and what state each is in.
extension AppModel {
    enum RowState: Equatable {
        case waiting
        case measuring
        case measured
        /// The scan stopped before reaching it.
        case notMeasured
        case cleaning
        /// Moved to the Trash or deleted; `outcome` says which.
        case cleaned
    }

    struct Row: Identifiable {
        let item: Item
        var state: RowState = .waiting
        var result: ItemResult?
        var progressBytes: Int64 = 0
        /// While deleting, how much is gone so far.
        var removedBytes: Int64 = 0
        /// While cleaning parts of it, their size; the whole otherwise.
        var cleaningKilobytes: Int64?
        var outcome: CleanOutcome?

        /// What the last scan found, shown dimmed until this scan reaches the item.
        var previous: ItemResult?

        var id: Item {
            self.item
        }

        var kilobytes: Int64 {
            self.result?.kilobytes ?? self.progressBytes / 1024
        }

        /// While cleaning, what is still on disk, counting down as it goes.
        var leftKilobytes: Int64 {
            max(0, self.kilobytes - self.removedBytes / 1024)
        }

        /// How far deleting has got, once it has removed something; moving
        /// to the Trash takes no time and has none.
        var cleaningProgress: Double? {
            let total = self.cleaningKilobytes ?? self.kilobytes
            guard self.state == .cleaning, self.removedBytes > 0, total > 0 else { return nil }
            return min(1, Double(self.removedBytes / 1024) / Double(total))
        }

        /// The size to show now: the new size once measured, the running count
        /// while measuring, the last scan's size before that.
        var shownKilobytes: Int64 {
            switch self.state {
            case .measured, .cleaning, .cleaned: self.result?.kilobytes ?? 0
            case .measuring: self.progressBytes / 1024
            case .waiting: self.previous.map { $0.isEmpty ? 0 : $0.kilobytes } ?? 0
            case .notMeasured: 0
            }
        }

        /// Showing the last scan's size, not this scan's.
        var showsPrevious: Bool {
            self.state == .waiting && self.previous != nil
        }

        /// Being measured and already counting.
        var isCounting: Bool {
            self.state == .measuring && self.progressBytes > 0
        }

        /// The result the inspector describes: this scan's, or the last one's.
        var shownResult: ItemResult? {
            self.result ?? self.previous
        }

        /// Measured, with something to reclaim.
        var isLive: Bool {
            self.state == .measured && !(self.result?.isEmpty ?? true)
        }

        var sizeKnown: Bool {
            self.result?.sizeKnown ?? true
        }

        /// Measured at some point, whatever happened since.
        var wasMeasured: Bool {
            [.measured, .cleaning, .cleaned].contains(self.state)
        }

        var canPutBack: Bool {
            self.state == .cleaned && (self.outcome?.canPutBack ?? false)
        }
    }
}

/// Xcode and Simulator, asked of `NSRunningApplication`, with a callback when
/// either launches or quits.
final class WorkspaceRunningApps: RunningAppsChecking, @unchecked Sendable {
    @MainActor var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    @MainActor
    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            self.observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let id = app?.bundleIdentifier,
                      DeveloperApp.allCases.contains(where: { $0.bundleIdentifier == id }) else { return }
                MainActor.assumeIsolated { self?.onChange?() }
            })
        }
    }

    func isRunning(_ app: DeveloperApp) async -> Bool {
        await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
                .contains { !$0.isTerminated }
        }
    }
}

// MARK: Cleaning parts of DerivedData

extension AppModel {
    /// A clean of some parts of DerivedData, which the inspector reports.
    struct PartsClean {
        let outcome: PartsCleanOutcome
        /// The breakdown before, to put parts back as they were measured.
        let before: DerivedDataBreakdown
        /// What it took from DerivedData's size.
        let kilobytes: Int64
        /// "2 projects".
        let summary: String

        var canPutBack: Bool {
            self.outcome.outcome.canPutBack
        }
    }

    var markedPartsKilobytes: Int64 {
        self.kilobytes(of: self.markedParts)
    }

    func kilobytes(of parts: Set<DerivedDataPart>) -> Int64 {
        guard let breakdown = self.rows[.derivedData]?.result?.derivedData else { return 0 }
        return parts.reduce(0) { $0 + breakdown.kilobytes(of: $1) }
    }

    func setMarked(_ part: DerivedDataPart, _ marked: Bool) {
        if marked { self.markedParts.insert(part) } else { self.markedParts.remove(part) }
    }

    /// "1 project", "2 projects", or "3 parts" once a cache or the rest is among them.
    nonisolated static func summary(of parts: Set<DerivedDataPart>) -> String {
        let projects = parts.allSatisfy {
            if case .project = $0 {
                true
            } else {
                false
            }
        }
        let noun = projects ? "project" : "part"
        return parts.count == 1 ? "1 \(noun)" : "\(parts.count) \(noun)s"
    }

    /// What a question calls these parts, largest first: "kite-1 and the
    /// compilation cache".
    func names(of parts: Set<DerivedDataPart>) -> [String] {
        guard let breakdown = self.rows[.derivedData]?.result?.derivedData else { return [] }
        let named: [(name: String, kilobytes: Int64)] = parts.map { part in
            (part.name(in: breakdown), breakdown.kilobytes(of: part))
        }
        return named.sorted { a, b in
            a.kilobytes != b.kilobytes ? a.kilobytes > b.kilobytes : a.name < b.name
        }.map(\.name)
    }

    /// Starts cleaning the ticked parts of DerivedData. The shared caches and
    /// the rest need Xcode and Simulator closed, as the whole folder does;
    /// projects alone can go while Xcode is open, after a question, since it
    /// may have one of them open.
    func requestCleanParts() async {
        guard !self.isScanning, !self.isCleaning, self.rows[.derivedData]?.isLive == true else { return }
        let parts = self.markedParts
        guard !parts.isEmpty else { return }
        await self.refreshRunningApps()
        let blocking = DeveloperApp.allCases.filter(self.runningApps.contains)
        if parts.contains(where: \.needsXcodeClosed), !blocking.isEmpty {
            self.pendingClean = PendingClean(
                items: [.derivedData],
                stage: .quitApps(blocking),
                parts: parts,
                partNames: self.names(of: parts),
                blockedPartNames: self.names(of: parts.filter(\.needsXcodeClosed)))
        } else {
            self.confirmOrClean([.derivedData], parts: parts)
        }
    }

    func performClean(_ parts: Set<DerivedDataPart>) async {
        guard let engine, !self.isCleaning, let row = self.rows[.derivedData], row.isLive,
              let result = row.result, let before = result.derivedData
        else { return }
        // Xcode may have been opened since the question was asked.
        if parts.contains(where: \.needsXcodeClosed) {
            await self.refreshRunningApps()
            if !self.runningApps.isEmpty {
                self.notice = Notice(title: "Nothing was cleaned", message: self.runningAppsSentence)
                return
            }
        }
        self.isCleaning = true
        let mode: CleanMode = self.moveToTrash ? .trash : .delete
        withAnimation(Motion.animation()) {
            self.rows[.derivedData]?.state = .cleaning
            self.rows[.derivedData]?.cleaningKilobytes = parts.reduce(0) { $0 + before.kilobytes(of: $1) }
        }
        let outcome = await self.countingDown(.derivedData) {
            await engine.clean(parts, of: result, mode: mode, progress: $0)
        }
        let cleaned = outcome.cleaned
        let freed = cleaned.reduce(0) { $0 + before.kilobytes(of: $1) }
        var left = result
        left.derivedData = before.removing(cleaned)
        left.kilobytes = result.kilobytes - freed
        withAnimation(Motion.animation(.easeInOut(duration: 0.4))) {
            self.rows[.derivedData]?.result = left
            self.rows[.derivedData]?.state = .measured
            self.rows[.derivedData]?.cleaningKilobytes = nil
            self.markedParts.subtract(cleaned)
        }
        if !cleaned.isEmpty {
            if outcome.outcome.canPutBack {
                self.trashedThisSession += freed
            } else {
                self.deletedThisSession += freed
            }
            self.lastPartsClean = PartsClean(
                outcome: outcome,
                before: before,
                kilobytes: freed,
                summary: Self.summary(of: cleaned))
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

    /// Moves what the last parts clean put in the Trash back where it was.
    func putBackParts() async {
        guard let engine, !self.isCleaning, let clean = self.lastPartsClean, clean.canPutBack,
              let result = self.rows[.derivedData]?.result, let current = result.derivedData
        else { return }
        let putBack = await engine.putBack(clean.outcome.outcome)
        let restored = clean.outcome.restored(by: putBack)
        let back = restored.reduce(0) { $0 + clean.before.kilobytes(of: $1) }
        var whole = result
        whole.derivedData = current.restoring(restored, from: clean.before)
        whole.kilobytes = result.kilobytes + back
        withAnimation(Motion.animation(.easeInOut(duration: 0.4))) {
            self.rows[.derivedData]?.result = whole
        }
        self.trashedThisSession = max(0, self.trashedThisSession - back)
        self.lastPartsClean = nil
        self.diskSpace = engine.diskSpace()
        self.saveScan()
        self.reportPutBackFailures(putBack.failed)
    }
}
