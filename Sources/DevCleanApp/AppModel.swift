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
    }

    struct Row: Identifiable {
        let item: Item
        var state: RowState = .waiting
        var result: ItemResult?
        var progressBytes: Int64 = 0

        var id: Item { item }
        var kilobytes: Int64 { result?.kilobytes ?? progressBytes / 1024 }
        /// Measured, with something to reclaim.
        var isLive: Bool { state == .measured && !(result?.isEmpty ?? true) }
        var sizeKnown: Bool { result?.sizeKnown ?? true }
    }

    var screen: Screen = .overview
    var chartStyle: ChartStyle = .ring
    var selection: Item?
    /// The runtime selected on the runtimes screen, by its simctl id.
    var selectedRuntime: String?
    /// The Xcode selected on the Xcode versions screen, by its path.
    var selectedXcode: String?
    var marked: Set<Item> = []
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
        guard let engine, !isScanning else { return }
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
            for item in scanOrder where rows[item]?.state != .measured {
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
        let measured = all.filter { $0.state == .measured }.sorted { $0.kilobytes > $1.kilobytes }
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
        let measured = family.items.contains { rows[$0]?.state == .measured }
        return measured ? kilobytes(of: family) : nil
    }

    var measuredCount: Int { scanOrder.filter { rows[$0]?.state == .measured }.count }

    var currentItem: Item? { scanOrder.first { rows[$0]?.state == .measuring } }

    var scanProgress: Double {
        scanOrder.isEmpty ? 0 : Double(measuredCount) / Double(scanOrder.count)
    }

    /// The weight a ring segment gets: its size once measured, otherwise what
    /// it took last time or the average so far, so the ring is whole from the start.
    func chartWeight(_ row: Row) -> Double {
        switch row.state {
        case .measured:
            return Double(max(row.kilobytes, 0))
        case .notMeasured:
            return 0
        case .waiting, .measuring:
            if let previous = previousKilobytes[row.item] { return Double(max(previous, 1)) }
            let measured = scanOrder.compactMap { rows[$0] }.filter { $0.state == .measured }
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
        return "\(scanned) \(runningAppsSentence)"
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
