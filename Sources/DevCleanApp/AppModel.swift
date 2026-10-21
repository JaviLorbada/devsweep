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

        var id: Item { item }
        var kilobytes: Int64 { result?.kilobytes ?? progressBytes / 1024 }
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
    private(set) var lastScan: Date?
    private(set) var diskSpace: DiskSpace?
    private(set) var extras: Extras?
    private(set) var projectFolders: ProjectFolders?
    private(set) var warnings: [String] = []
    private(set) var runningApps: Set<DeveloperApp> = []
    let volumeName: String
    let engine: Engine?
    let startupError: String?

    /// Sizes from the previous scan, so unmeasured segments keep their place.
    private var previousKilobytes: [Item: Int64] = [:]
    private var marksTouched = false
    private var scanTask: Task<Void, Never>?
    private let workspaceApps: WorkspaceRunningApps

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let workspaceApps = WorkspaceRunningApps()
        self.workspaceApps = workspaceApps
        var tools = Tools.live(environment: environment)
        tools.runningApps = workspaceApps
        #if DEBUG
        // Trying the app against a fake home shouldn't fill the real Trash.
        if let folder = environment["DEVCLEAN_TRASH_FOLDER"] {
            tools.trash = FolderTrash(folder: folder)
        }
        #endif
        do {
            engine = try Engine(config: ScanConfig.fromEnvironment(environment), tools: tools)
            startupError = nil
        } catch {
            engine = nil
            startupError = error.description
        }
        volumeName = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]))?
            .volumeLocalizedName ?? "Macintosh HD"
        rows = Dictionary(uniqueKeysWithValues: (engine?.items ?? []).map { ($0, Row(item: $0)) })
        scanOrder = engine?.items ?? []
        diskSpace = engine?.diskSpace()
        workspaceApps.onChange = { [weak self] in
            Task { await self?.refreshRunningApps() }
        }
    }

    // MARK: Scanning

    func scan() {
        guard let engine, !isScanning, !isCleaning else { return }
        for (item, row) in rows where row.result != nil {
            previousKilobytes[item] = row.kilobytes
        }
        rows = Dictionary(uniqueKeysWithValues: engine.items.map { ($0, Row(item: $0)) })
        scanOrder = engine.items
        warnings = []
        marksTouched = false
        marked = []
        isScanning = true
        isLoadingExtras = engine.config.includeExtras

        scanTask = Task {
            await refreshRunningApps()
            for await event in engine.scan() {
                apply(event)
            }
            finishScan()
        }
    }

    func stopScan() {
        scanTask?.cancel()
    }

    private func apply(_ event: ScanEvent) {
        switch event {
        case .projectFolders(let folders):
            projectFolders = folders
        case .started(let item):
            withAnimation(.easeInOut(duration: 0.25)) { rows[item]?.state = .measuring }
        case .progress(let item, let bytes):
            rows[item]?.progressBytes = bytes
        case .warning(let message):
            warnings.append(message)
        case .finished(let result):
            withAnimation(.easeInOut(duration: 0.4)) {
                rows[result.item]?.result = result
                rows[result.item]?.state = .measured
            }
        case .done:
            diskSpace = engine?.diskSpace()
            lastScan = Date()
            withAnimation { isScanning = false }
            applyDefaultMarks()
            if selection == nil { selection = orderedRows.first?.item }
        case .extras(let extras):
            withAnimation { self.extras = extras }
            isLoadingExtras = false
        }
    }

    private func finishScan() {
        isLoadingExtras = false
        guard isScanning else { return }
        // Stopped before the end: what wasn't reached stays unmeasured.
        withAnimation {
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

    /// Measured items largest first, then the one being measured, then the rest in scan order.
    var orderedRows: [Row] {
        let all = scanOrder.compactMap { rows[$0] }
        let measured = all.filter(\.wasMeasured).sorted { $0.kilobytes > $1.kilobytes }
        return measured + all.filter { $0.state == .measuring } + all.filter { $0.state == .waiting || $0.state == .notMeasured }
    }

    var liveRows: [Row] { orderedRows.filter(\.isLive) }

    var markedRows: [Row] { liveRows.filter { marked.contains($0.item) } }

    var reclaimableKilobytes: Int64 { liveRows.reduce(0) { $0 + $1.kilobytes } }

    var markedKilobytes: Int64 { markedRows.reduce(0) { $0 + $1.kilobytes } }

    func kilobytes(of family: Family) -> Int64 {
        liveRows.filter { $0.item.family == family }.reduce(0) { $0 + $1.kilobytes }
    }

    /// The family's size once any of its items is measured, nil before.
    func measuredKilobytes(of family: Family) -> Int64? {
        let measured = family.items.contains { rows[$0]?.wasMeasured ?? false }
        return measured ? kilobytes(of: family) : nil
    }

    var measuredCount: Int { scanOrder.filter { rows[$0]?.wasMeasured ?? false }.count }

    var currentItem: Item? { scanOrder.first { rows[$0]?.state == .measuring } }

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
        case .waiting, .measuring:
            if let previous = previousKilobytes[row.item] { return Double(max(previous, 1)) }
            let measured = scanOrder.compactMap { rows[$0] }.filter(\.wasMeasured)
            let total = measured.reduce(0) { $0 + Double($1.kilobytes) }
            return measured.isEmpty || total == 0 ? 1 : total / Double(measured.count)
        }
    }

    var statusLine: String {
        if let startupError { return startupError }
        if isScanning {
            return "Scanning \(min(measuredCount + 1, scanOrder.count)) of \(scanOrder.count) items"
        }
        guard lastScan != nil else { return "Not scanned yet" }
        let unmeasured = scanOrder.filter { rows[$0]?.state == .notMeasured }.count
        let scanned = unmeasured > 0
            ? "Stopped after \(measuredCount) of \(scanOrder.count) items."
            : "Scanned just now, \(scanOrder.count) items."
        var line = "\(scanned) \(runningAppsSentence)"
        if trashedThisSession > 0 {
            line += " \(SizeText.of(kilobytes: trashedThisSession)) moved to Trash this session."
        }
        if deletedThisSession > 0 {
            line += " \(SizeText.of(kilobytes: deletedThisSession)) deleted this session."
        }
        return line
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
    var runtimesKilobytes: Int64? { extras.map { $0.runtimes.reduce(0) { $0 + $1.kilobytes } } }

    func tilde(_ path: String) -> String {
        engine?.policy.tilde(path) ?? path
    }

    #if DEBUG
    /// Puts the model back to the moment `measured` items were done, for snapshots.
    func rewindScan(toMeasured measured: Int) {
        for (index, item) in scanOrder.enumerated() where index >= measured {
            guard var row = rows[item] else { continue }
            previousKilobytes[item] = row.kilobytes
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
            withAnimation { rows[item]?.state = .cleaning }
            let outcome = await engine.clean(result, mode: mode)
            problems += outcome.warnings
            let removedSomething = !outcome.removed.isEmpty || outcome.toolSucceeded == true
            withAnimation(.easeInOut(duration: 0.4)) {
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
        warnings += problems
        if !problems.isEmpty {
            notice = Notice(title: "Some things were left alone", message: problems.joined(separator: "\n"))
        }
    }

    /// Moves what cleaning `item` put in the Trash back where it was.
    func putBack(_ item: Item) async {
        guard let engine, let row = rows[item], row.canPutBack, let outcome = row.outcome else { return }
        let result = await engine.putBack(outcome)
        withAnimation(.easeInOut(duration: 0.4)) {
            if !result.restored.isEmpty {
                rows[item]?.state = .measured
                rows[item]?.outcome = nil
                trashedThisSession = max(0, trashedThisSession - row.kilobytes)
            }
        }
        diskSpace = engine.diskSpace()
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

    var staleDays: Int { engine?.config.staleDays ?? 90 }

    /// The selected runtime, or the first flagged one, or the first.
    var currentRuntime: SimulatorRuntime? {
        let runtimes = extras?.runtimes ?? []
        return runtimes.first { $0.id == selectedRuntime }
            ?? runtimes.first { $0.flagReason(staleDays: staleDays) != nil }
            ?? runtimes.first
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
        withAnimation { extras = fresh }
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
