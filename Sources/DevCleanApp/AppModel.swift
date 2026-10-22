import AppKit
import DevCleanKit
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
    }

    enum ChartStyle: String, CaseIterable, Identifiable {
        case ring = "Ring"
        case blocks = "Blocks"
        var id: Self { self }
    }

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
        var outcome: CleanOutcome?

        /// What the last scan found, shown dimmed until this scan reaches the item.
        var previous: ItemResult?

        var id: Item { item }
        var kilobytes: Int64 { result?.kilobytes ?? progressBytes / 1024 }

        /// The size to show now: the new size once measured, the running count
        /// while measuring, the last scan's size before that.
        var shownKilobytes: Int64 {
            switch state {
            case .measured, .cleaning, .cleaned: result?.kilobytes ?? 0
            case .measuring: progressBytes / 1024
            case .waiting: previous.map { $0.isEmpty ? 0 : $0.kilobytes } ?? 0
            case .notMeasured: 0
            }
        }

        /// Showing the last scan's size, not this scan's.
        var showsPrevious: Bool { state == .waiting && previous != nil }

        /// Being measured and already counting.
        var isCounting: Bool { state == .measuring && progressBytes > 0 }

        /// The result the inspector describes: this scan's, or the last one's.
        var shownResult: ItemResult? { result ?? previous }
        /// Measured, with something to reclaim.
        var isLive: Bool { state == .measured && !(result?.isEmpty ?? true) }
        var sizeKnown: Bool { result?.sizeKnown ?? true }
        /// Measured at some point, whatever happened since.
        var wasMeasured: Bool { [.measured, .cleaning, .cleaned].contains(state) }
        var canPutBack: Bool { state == .cleaned && (outcome?.canPutBack ?? false) }
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
    }

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var screen: Screen = .overview
    var chartStyle: ChartStyle = .ring
    var selection: Item?
    /// The runtime selected on the runtimes screen, by its simctl id.
    var selectedRuntime: String?
    /// The Xcode selected on the Xcode versions screen, by its path.
    var selectedXcode: String?
    var marked: Set<Item> = []
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
    private let environment: [String: String]
    private let tools: Tools

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
    private var store: ScanStore?
    /// Progress that arrived since the screen last showed it.
    private var pendingProgress: [Item: Int64] = [:]
    private var progressFlush: Task<Void, Never>?
    private var marksTouched = false
    private var scanTask: Task<Void, Never>?
    private let workspaceApps: WorkspaceRunningApps

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        store: ScanStore? = nil,
        preferences: Preferences? = nil
    ) {
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
        var tools = Tools.live(environment: environment)
        tools.runningApps = workspaceApps
        #if DEBUG
        // Trying the app against a fake home shouldn't fill the real Trash.
        if let folder = environment["DEVCLEAN_TRASH_FOLDER"] {
            tools.trash = FolderTrash(folder: folder)
        }
        #endif
        self.environment = environment
        self.tools = tools
        moveToTrash = preferences.moveToTrash
        (engine, startupError) = Self.makeEngine(preferences: preferences, environment: environment, tools: tools)
        volumeName = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]))?
            .volumeLocalizedName ?? "Macintosh HD"
        rows = Dictionary(uniqueKeysWithValues: (engine?.items ?? []).map { ($0, Row(item: $0)) })
        scanOrder = engine?.items ?? []
        diskSpace = engine?.diskSpace()
        self.store = store ?? engine.map { ScanStore.standard(home: $0.config.home) }
        restorePreviousScan()
        workspaceApps.onChange = { [weak self] in
            Task { await self?.refreshRunningApps() }
        }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.now = Date()
            }
        }
    }

    private static func makeEngine(preferences: Preferences, environment: [String: String], tools: Tools) -> (Engine?, String?) {
        var config = preferences.scanConfig(environment: environment)
        #if DEBUG
        if let skip = environment["DEVCLEAN_SKIP"], let items = try? ScanConfig.parseSkip(skip) {
            config.skipped.formUnion(items)
        }
        #endif
        do {
            return (try Engine(config: config, tools: tools), nil)
        } catch {
            return (nil, error.description)
        }
    }

    /// Shows the last launch's scan of this home, dimmed, until this one replaces it.
    private func restorePreviousScan() {
        guard let engine, let saved = store?.load(home: engine.policy.homeReal) else { return }
        for result in saved.results {
            rows[result.item]?.previous = result
        }
        extras = saved.extras
        android = saved.android
        previousScanDate = saved.date
    }

    /// Keeps this scan's results for the next launch. Cleaned items are kept
    /// as found nothing, since they are gone.
    private func saveScan() {
        guard let engine, let store else { return }
        let results: [ItemResult] = scanOrder.compactMap { item in
            guard let row = rows[item], var result = row.result, row.wasMeasured else { return nil }
            if row.state == .cleaned {
                result.paths = []
                result.kilobytes = 0
                result.derivedData = nil
            }
            return result
        }
        guard results.count == scanOrder.count else { return }
        let scan = SavedScan(date: lastScan ?? Date(), home: engine.policy.homeReal, results: results, extras: extras, android: android)
        try? store.save(scan)
    }

    // MARK: Scanning

    func scan() {
        guard !isScanning, !isCleaning else { return }
        // Preferences changed since the last scan apply from this one.
        (engine, startupError) = Self.makeEngine(preferences: preferences, environment: environment, tools: tools)
        guard let engine else { return }
        // What was on screen becomes the dimmed "last scan" until replaced.
        rows = Dictionary(uniqueKeysWithValues: engine.items.map { item in
            var row = Row(item: item)
            row.previous = rows[item]?.result ?? rows[item]?.previous
            return (item, row)
        })
        if lastScan != nil { previousScanDate = lastScan }
        scanOrder = engine.items
        warnings = []
        marksTouched = false
        marked = []
        isScanning = true
        isLoadingExtras = engine.config.includeExtras
        isLoadingAndroid = engine.config.includeAndroid
        scanStarted = .now
        itemsDone = nil
        extrasDone = nil
        androidDone = nil
        scanTiming = nil

        scanTask = Task {
            await refreshRunningApps()
            for await event in engine.scan(.interactive) {
                apply(event)
            }
            flushProgress()
            finishScan()
            scanTask = nil
        }
    }

    /// Whether a scan's task is still winding down, even after `isScanning` turned false.
    var isScanTaskRunning: Bool { scanTask != nil }

    func stopScan() {
        scanTask?.cancel()
    }

    private func apply(_ event: ScanEvent) {
        switch event {
        case .projectFolders(let folders):
            projectFolders = folders
        case .started(let item):
            withAnimation(Motion.animation(.easeInOut(duration: 0.25))) { rows[item]?.state = .measuring }
        case .progress(let item, let bytes):
            // Several walks report thousands of times a second; the screen
            // shows the latest count about ten times a second.
            pendingProgress[item] = bytes
            if progressFlush == nil {
                progressFlush = Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    flushProgress()
                }
            }
        case .warning(let message):
            warnings.append(message)
        case .finished(let result):
            pendingProgress[result.item] = nil
            withAnimation(Motion.animation(.easeInOut(duration: 0.4))) {
                rows[result.item]?.result = result
                rows[result.item]?.state = .measured
            }
        case .done:
            itemsDone = secondsSinceScanStarted
            diskSpace = engine?.diskSpace()
            lastScan = Date()
            now = Date()
            previousScanDate = nil
            withAnimation(Motion.animation()) { isScanning = false }
            applyDefaultMarks()
            if selection == nil { selection = orderedRows.first?.item }
            finishTiming()
        case .extras(let extras):
            withAnimation(Motion.animation()) { self.extras = extras }
            isLoadingExtras = false
            extrasDone = secondsSinceScanStarted
            finishTiming()
        case .android(let report):
            withAnimation(Motion.animation()) { android = report }
            isLoadingAndroid = false
            androidDone = secondsSinceScanStarted
            finishTiming()
        }
    }

    private func flushProgress() {
        progressFlush = nil
        for (item, bytes) in pendingProgress where rows[item]?.state == .measuring {
            rows[item]?.progressBytes = bytes
        }
        pendingProgress = [:]
    }

    private var secondsSinceScanStarted: Double? {
        scanStarted.map { start in
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
        scanTiming = (itemsDone, max(itemsDone, extrasDone ?? 0, androidDone ?? 0))
        saveScan()
    }

    private func finishScan() {
        isLoadingExtras = false
        isLoadingAndroid = false
        guard isScanning else { return }
        // Stopped before the end: what wasn't reached stays unmeasured.
        withAnimation(Motion.animation()) {
            for item in scanOrder where !(rows[item]?.wasMeasured ?? false) {
                rows[item]?.state = .notMeasured
                rows[item]?.progressBytes = 0
            }
            isScanning = false
        }
        lastScan = Date()
        diskSpace = engine?.diskSpace()
        applyDefaultMarks()
    }

    /// The three biggest items start marked, unless marks were changed during the scan.
    private func applyDefaultMarks() {
        guard !marksTouched else { return }
        marked = Set(liveRows.prefix(3).map(\.item))
    }

    func refreshRunningApps() async {
        var running = Set<DeveloperApp>()
        for app in DeveloperApp.allCases where await workspaceApps.isRunning(app) {
            running.insert(app)
        }
        runningApps = running
    }

    // MARK: Marks and selection

    func setMarked(_ item: Item, _ isMarked: Bool) {
        marksTouched = true
        if isMarked { marked.insert(item) } else { marked.remove(item) }
    }

    func markAll() {
        marksTouched = true
        marked = Set(liveRows.map(\.item))
    }

    func markNone() {
        marksTouched = true
        marked = []
    }

    /// Selects the biggest item of a family on the overview.
    func pick(_ family: Family) {
        screen = .overview
        if let biggest = liveRows.first(where: { $0.item.family == family }) ?? orderedRows.first(where: { $0.item.family == family }) {
            selection = biggest.item
        }
    }

    // MARK: Derived values

    /// Measured items largest first, then the ones being measured, then the
    /// rest; those two by what the last scan found, so rows keep their places.
    var orderedRows: [Row] {
        let all = scanOrder.compactMap { rows[$0] }
        let byPrevious = { (a: Row, b: Row) in (a.previous?.kilobytes ?? 0) > (b.previous?.kilobytes ?? 0) }
        let measured = all.filter(\.wasMeasured).sorted { $0.kilobytes > $1.kilobytes }
        return measured + all.filter { $0.state == .measuring }.sorted(by: byPrevious)
            + all.filter { $0.state == .waiting || $0.state == .notMeasured }.sorted(by: byPrevious)
    }

    var liveRows: [Row] { orderedRows.filter(\.isLive) }

    var markedRows: [Row] { liveRows.filter { marked.contains($0.item) } }

    /// Rows whose size counts toward the totals on screen: measured with
    /// something to reclaim, counting up, or still showing the last scan.
    private var countedRows: [Row] {
        orderedRows.filter { $0.isLive || $0.isCounting || $0.showsPrevious }
    }

    /// The total on screen: this scan's sizes where it has them, the running
    /// counts, and the last scan's sizes for what it hasn't reached yet.
    var reclaimableKilobytes: Int64 { countedRows.reduce(0) { $0 + $1.shownKilobytes } }

    var markedKilobytes: Int64 { markedRows.reduce(0) { $0 + $1.kilobytes } }

    func kilobytes(of family: Family) -> Int64 {
        countedRows.filter { $0.item.family == family }.reduce(0) { $0 + $1.shownKilobytes }
    }

    /// The family's size once anything is known about it, nil before.
    func measuredKilobytes(of family: Family) -> Int64? {
        let known = family.items.contains { item in
            guard let row = rows[item] else { return false }
            return row.wasMeasured || row.isCounting || row.showsPrevious
        }
        return known ? kilobytes(of: family) : nil
    }

    /// Whether everything shown for the family comes from the last scan.
    func familyShowsPrevious(_ family: Family) -> Bool {
        let rows = family.items.compactMap { self.rows[$0] }
        return rows.contains(where: \.showsPrevious) && !rows.contains { $0.wasMeasured || $0.isCounting }
    }

    /// Whether the totals still lean on the last scan.
    var showsPrevious: Bool { scanOrder.contains { rows[$0]?.showsPrevious ?? false } }

    var measuredCount: Int { scanOrder.filter { rows[$0]?.wasMeasured ?? false }.count }

    var measuringItems: [Item] { scanOrder.filter { rows[$0]?.state == .measuring } }

    var currentItem: Item? { measuringItems.first }

    var scanProgress: Double {
        scanOrder.isEmpty ? 0 : Double(measuredCount) / Double(scanOrder.count)
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
            let measured = scanOrder.compactMap { rows[$0] }.filter(\.wasMeasured)
            let total = measured.reduce(0) { $0 + Double($1.kilobytes) }
            return measured.isEmpty || total == 0 ? 1 : total / Double(measured.count)
        }
    }

    var statusLine: String {
        if let startupError { return startupError }
        if isScanning {
            let progress = "Scanning, \(measuredCount) of \(scanOrder.count) items measured"
            if let previousScanDate, showsPrevious {
                return "Last scanned \(Self.relative(previousScanDate, to: now)). \(progress)."
            }
            return progress
        }
        guard let lastScan else {
            return previousScanDate.map { "Last scanned \(Self.relative($0, to: now))." } ?? "Not scanned yet"
        }
        let unmeasured = scanOrder.filter { rows[$0]?.state == .notMeasured }.count
        let scanned = unmeasured > 0
            ? "Stopped after \(measuredCount) of \(scanOrder.count) items."
            : "Scanned \(Self.relative(lastScan, to: now)), \(scanOrder.count) items."
        var line = "\(scanned) \(runningAppsSentence)"
        if trashedThisSession > 0 {
            line += " \(SizeText.of(kilobytes: trashedThisSession)) moved to Trash this session."
        }
        if deletedThisSession > 0 {
            line += " \(SizeText.of(kilobytes: deletedThisSession)) deleted this session."
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
        switch (runningApps.contains(.xcode), runningApps.contains(.simulator)) {
        case (false, false): "Xcode and Simulator are closed."
        case (true, false): "Xcode is open."
        case (false, true): "Simulator is open."
        case (true, true): "Xcode and Simulator are open."
        }
    }

    var xcodesKilobytes: Int64? { extras.map { $0.xcodes.reduce(0) { $0 + $1.kilobytes } } }
    var androidStudiosKilobytes: Int64? { android.map { total($0.studios) } }
    var androidSDKKilobytes: Int64? { android.map { total($0.sdkEntries + $0.emulators) } }
    var gradleCachesKilobytes: Int64? { android.map { total($0.gradleCaches) } }

    private func total(_ entries: [AndroidEntry]) -> Int64 {
        entries.reduce(0) { $0 + $1.kilobytes }
    }
    var runtimesKilobytes: Int64? { extras.map { $0.runtimes.reduce(0) { $0 + $1.kilobytes } } }

    func tilde(_ path: String) -> String {
        engine?.policy.tilde(path) ?? path
    }

    /// Shows results as if a scan had just measured them, without scanning.
    /// For tests.
    func showResults(_ results: [ItemResult]) {
        for result in results {
            rows[result.item]?.result = result
            rows[result.item]?.state = .measured
        }
        lastScan = Date()
        selection = orderedRows.first?.item
    }

    #if DEBUG
    /// Whether the window shows its inspector, for the launch harness's report.
    var debugInspectorShown = false

    /// Puts the model back to the moment `measured` items were done, for snapshots.
    func rewindScan(toMeasured measured: Int) {
        for (index, item) in scanOrder.enumerated() where index >= measured {
            guard var row = rows[item] else { continue }
            row.previous = row.result
            row.progressBytes = index == measured ? row.kilobytes * 1024 / 3 : 0
            row.state = index == measured ? .measuring : .waiting
            row.result = nil
            rows[item] = row
        }
        isScanning = true
        marked = []
    }
    #endif

    // MARK: Cleaning

    /// Starts cleaning `items`: asks to quit Xcode and Simulator when an Xcode
    /// item needs them closed, and asks to confirm anything that can't be put back.
    func requestClean(_ items: [Item]) async {
        guard !isScanning, !isCleaning else { return }
        let items = items.filter { rows[$0]?.isLive ?? false }
        guard !items.isEmpty else { return }
        await refreshRunningApps()
        let blocking = DeveloperApp.allCases.filter(runningApps.contains)
        if items.contains(where: \.needsXcodeClosed), !blocking.isEmpty {
            pendingClean = PendingClean(items: items, stage: .quitApps(blocking))
        } else {
            confirmOrClean(items)
        }
    }

    /// Quits Xcode and Simulator, then goes on with the clean.
    func quitAppsAndClean(_ pending: PendingClean) async {
        pendingClean = nil
        guard case .quitApps(let apps) = pending.stage else { return }
        if await quit(apps) {
            confirmOrClean(pending.items, afterAlert: true)
        } else {
            notice = Notice(
                title: "\(apps.map(\.rawValue).joined(separator: " and ")) didn't quit",
                message: "Nothing was cleaned. Quit them yourself, for example after saving your work, and clean again."
            )
        }
    }

    /// Goes on with the items that don't need Xcode closed.
    func cleanSkippingXcodeItems(_ pending: PendingClean) {
        pendingClean = nil
        let rest = pending.items.filter { !$0.needsXcodeClosed }
        if !rest.isEmpty { confirmOrClean(rest, afterAlert: true) }
    }

    func confirmClean(_ pending: PendingClean) async {
        pendingClean = nil
        await performClean(pending.items)
    }

    /// Whether these items need a yes first: everything does when deleting
    /// for good, and Simulators and Homebrew always, since their tools delete them.
    func needsConfirmation(_ items: [Item]) -> Bool {
        !moveToTrash || items.contains(where: \.cleanedByItsTool)
    }

    /// - Parameter afterAlert: an alert is closing, so give it a moment
    ///   before showing the next one.
    private func confirmOrClean(_ items: [Item], afterAlert: Bool = false) {
        if needsConfirmation(items) {
            Task {
                if afterAlert { try? await Task.sleep(for: .milliseconds(300)) }
                pendingClean = PendingClean(items: items, stage: .confirm)
            }
        } else {
            Task { await performClean(items) }
        }
    }

    private func performClean(_ items: [Item]) async {
        guard let engine, !isCleaning else { return }
        isCleaning = true
        let mode: CleanMode = moveToTrash ? .trash : .delete
        var problems: [String] = []

        for item in items {
            guard let row = rows[item], row.isLive, let result = row.result else { continue }
            // Xcode may have been opened since the question was asked.
            if item.needsXcodeClosed {
                await refreshRunningApps()
                if !runningApps.isEmpty {
                    problems.append("Skipped \(item.name): \(runningAppsSentence)")
                    continue
                }
            }
            withAnimation(Motion.animation()) { rows[item]?.state = .cleaning }
            let outcome = await engine.clean(result, mode: mode)
            problems += outcome.warnings
            let removedSomething = !outcome.removed.isEmpty || outcome.toolSucceeded == true
            withAnimation(Motion.animation(.easeInOut(duration: 0.4))) {
                if removedSomething {
                    rows[item]?.state = .cleaned
                    rows[item]?.outcome = outcome
                    marked.remove(item)
                    if outcome.canPutBack {
                        trashedThisSession += result.kilobytes
                    } else {
                        deletedThisSession += result.kilobytes
                    }
                } else {
                    rows[item]?.state = .measured
                }
            }
        }

        isCleaning = false
        diskSpace = engine.diskSpace()
        saveScan()
        warnings += problems
        if !problems.isEmpty {
            notice = Notice(title: "Some things were left alone", message: problems.joined(separator: "\n"))
        }
    }

    /// Moves what cleaning `item` put in the Trash back where it was.
    func putBack(_ item: Item) async {
        guard let engine, let row = rows[item], row.canPutBack, let outcome = row.outcome else { return }
        let result = await engine.putBack(outcome)
        withAnimation(Motion.animation(.easeInOut(duration: 0.4))) {
            if !result.restored.isEmpty {
                rows[item]?.state = .measured
                rows[item]?.outcome = nil
                trashedThisSession = max(0, trashedThisSession - row.kilobytes)
            }
        }
        diskSpace = engine.diskSpace()
        saveScan()
        if !result.failed.isEmpty {
            notice = Notice(
                title: "Some folders couldn't be put back",
                message: "Something now stands where they were, or the folder that held them changed. They are still in the Trash:\n"
                    + result.failed.map(tilde).joined(separator: "\n")
            )
        }
    }

    // MARK: Xcodes and runtimes

    /// The runtime waiting on the removal sheet.
    var runtimeToRemove: SimulatorRuntime?
    private(set) var isRemovingRuntime = false
    var runtimeRemovalError: String?

    var staleDays: Int { preferences.staleDays }

    /// The selected runtime, or the first flagged one, or the first.
    var currentRuntime: SimulatorRuntime? {
        let runtimes = extras?.runtimes ?? []
        return runtimes.first { $0.id == selectedRuntime }
            ?? runtimes.first { $0.flagReason(staleDays: staleDays) != nil }
            ?? runtimes.first
    }

    /// What the current Android screen lists, in the order it shows them.
    var androidEntries: [AndroidEntry] {
        guard let android else { return [] }
        switch screen {
        case .androidStudios: return android.studios
        case .androidSDK: return android.emulators + android.systemImages + android.platforms + android.buildTools + android.otherSDKParts
        case .gradleCaches: return android.gradleCaches
        default: return []
        }
    }

    /// The selected Android entry on this screen, or the first flagged one, or the first.
    var currentAndroidEntry: AndroidEntry? {
        let entries = androidEntries
        return entries.first { $0.path == selectedAndroidEntry }
            ?? entries.first { $0.flagReason(staleDays: staleDays) != nil }
            ?? entries.first
    }

    var currentXcode: InstalledXcode? {
        let xcodes = extras?.xcodes ?? []
        return xcodes.first { $0.path == selectedXcode } ?? xcodes.first { $0.isSelected } ?? xcodes.first
    }

    /// The subtitle under each screen's title.
    var subtitle: String {
        switch screen {
        case .overview:
            return statusLine
        case .simulatorRuntimes:
            guard let runtimes = extras?.runtimes else { return isLoadingExtras ? "Listing runtimes" : "" }
            let count = runtimes.count == 1 ? "1 runtime" : "\(runtimes.count) runtimes"
            return "\(SizeText.of(kilobytes: runtimesKilobytes ?? 0)) in \(count). devclean never removes these on its own."
        case .xcodeVersions:
            guard let xcodes = extras?.xcodes else { return isLoadingExtras ? "Listing Xcodes" : "" }
            let count = xcodes.count == 1 ? "1 Xcode" : "\(xcodes.count) Xcodes"
            return "\(SizeText.of(kilobytes: xcodesKilobytes ?? 0)) in \(count). devclean never removes these."
        case .androidStudios:
            guard let studios = android?.studios else { return isLoadingAndroid ? "Listing Android Studio" : "" }
            let count = studios.count == 1 ? "1 install" : "\(studios.count) installs"
            return "\(SizeText.of(kilobytes: androidStudiosKilobytes ?? 0)) in \(count). devclean never removes these."
        case .androidSDK:
            guard android != nil else { return isLoadingAndroid ? "Listing the SDK and emulators" : "" }
            return "\(SizeText.of(kilobytes: androidSDKKilobytes ?? 0)) in the SDK and emulators. devclean never removes these."
        case .gradleCaches:
            guard android != nil else { return isLoadingAndroid ? "Listing Gradle's caches" : "" }
            return "\(SizeText.of(kilobytes: gradleCachesKilobytes ?? 0)) in ~/.gradle. devclean never removes these."
        }
    }

    /// Removes the runtime on the sheet through simctl, then lists runtimes again.
    func removeRuntime(_ runtime: SimulatorRuntime) async {
        guard let engine, !isRemovingRuntime else { return }
        isRemovingRuntime = true
        runtimeRemovalError = nil
        let removed = await engine.removeRuntime(runtime)
        isRemovingRuntime = false
        if removed {
            runtimeToRemove = nil
            selectedRuntime = nil
            await refreshExtras()
            diskSpace = engine.diskSpace()
        } else {
            runtimeRemovalError = "simctl couldn't remove it. Run the command in Terminal to see why; "
                + "a simulator using it may still be running."
        }
    }

    func refreshExtras() async {
        guard let engine else { return }
        isLoadingExtras = true
        let fresh = await engine.extras()
        withAnimation(Motion.animation()) { extras = fresh }
        isLoadingExtras = false
    }

    /// Asks the apps to quit, as choosing Quit would, and waits up to 15 seconds.
    private func quit(_ apps: [DeveloperApp]) async -> Bool {
        let running = apps.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleIdentifier) }
        running.forEach { $0.terminate() }
        for _ in 0..<60 {
            if running.allSatisfy(\.isTerminated) { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        await refreshRunningApps()
        return running.allSatisfy(\.isTerminated)
    }

    // MARK: Finder

    func revealInFinder(_ paths: [String]) {
        let urls = paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
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
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let id = app?.bundleIdentifier, DeveloperApp.allCases.contains(where: { $0.bundleIdentifier == id }) else { return }
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
