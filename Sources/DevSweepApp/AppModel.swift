import AppKit
import DevSweepKit
import Observation
import SwiftUI

/// Builds the shared models and wires them together, and holds what each
/// screen shows until the screens get models of their own.
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

    let preferences: Preferences
    let notifier: NotificationPoster
    let scan: ScanModel
    let marks: MarksModel
    let runningApps: RunningAppsModel
    let cleaning: CleaningModel

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
    /// The Android entry selected on its screen, by path.
    var selectedAndroidEntry: String?
    /// The last growth alert posted, for the menu bar panel.
    private(set) var lastAlert: GrowthCheck.Alert?

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        store: (any ScanMemoryStore)? = nil,
        preferences: Preferences? = nil,
        notifier: NotificationPoster = UserNotificationPoster(),
        dependencies: Dependencies? = nil,
        quitter: (any AppQuitting)? = nil)
    {
        self.notifier = notifier
        let preferences = preferences ?? Preferences()
        self.preferences = preferences
        let workspaceApps = WorkspaceRunningApps()
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

        let scan = ScanModel(
            environment: environment,
            store: store,
            preferences: preferences,
            dependencies: dependencies)
        let marks = MarksModel(scan: scan)
        let runningApps = RunningAppsModel(
            checker: dependencies.tools.runningApps,
            quitter: quitter ?? WorkspaceAppQuitter())
        self.scan = scan
        self.marks = marks
        self.runningApps = runningApps
        self.cleaning = CleaningModel(
            scan: scan,
            marks: marks,
            apps: runningApps,
            moveToTrash: preferences.moveToTrash)

        self.wire()
        workspaceApps.onChange = { [weak runningApps] in
            Task { await runningApps?.refresh() }
        }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.tick(now: Date())
            }
        }
    }

    /// What a scan's start and end set off in the other models.
    private func wire() {
        self.scan.onStart = { [weak self] in
            guard let self else { return }
            self.marks.reset()
            self.cleaning.reset()
            Task { await self.runningApps.refresh() }
        }
        self.scan.onItemsMeasured = { [weak self] stopped in
            guard let self else { return }
            self.marks.applyDefaults()
            if !stopped, self.selection == nil { self.selection = self.scan.tally.ordered.first?.item }
        }
        self.scan.onFinished = { [weak self] in
            self?.checkGrowth()
        }
    }

    /// Every half minute: the clock for "3 minutes ago", the free space for
    /// the menu bar, and a scan once the last one is a day old.
    func tick(now: Date) {
        self.scan.tick(now: now)
        if ScanSchedule.isDue(lastScan: self.scan.lastScan, now: now), !self.scan.isScanning,
           !self.scan.isCleaning
        {
            self.scan.scan()
        }
    }

    /// Posts a notification when DerivedData grew past the threshold since
    /// the last scan.
    private func checkGrowth() {
        let derivedData = self.scan.rows[.derivedData]
        guard let alert = GrowthCheck.derivedData(
            previousKilobytes: derivedData?.previous?.kilobytes,
            currentKilobytes: derivedData?.result?.kilobytes,
            thresholdGigabytes: self.preferences.derivedDataGrowthGigabytes) else { return }
        self.lastAlert = alert
        let notifier = self.notifier
        Task { await notifier.post(title: alert.title, body: alert.body) }
    }

    // MARK: Overview

    /// Selects the biggest item of a family on the overview.
    func pick(_ family: Family) {
        self.screen = .overview
        let tally = self.scan.tally
        if let biggest = tally.live.first(where: { $0.item.family == family }) ?? tally.ordered
            .first(where: { $0.item.family == family })
        {
            self.selection = biggest.item
        }
    }

    var statusLine: String {
        StatusText.overview(
            self.scan.statusFacts,
            runningApps: self.runningApps.running,
            trashedKilobytes: self.cleaning.trashedThisSession,
            deletedKilobytes: self.cleaning.deletedThisSession)
    }

    /// The subtitle under each screen's title.
    var subtitle: String {
        let scan = self.scan
        return switch self.screen {
        case .overview:
            // A development build says what it was built from, so an old
            // bundle can't pass for the latest.
            [self.statusLine, BuildIdentity.current.statusNote].compactMap(\.self).joined(separator: " ")
        case .simulatorRuntimes: StatusText.runtimes(scan.extras?.runtimes, isLoading: scan.isLoadingExtras)
        case .xcodeVersions: StatusText.xcodes(scan.extras?.xcodes, isLoading: scan.isLoadingExtras)
        case .androidStudios: StatusText.androidStudios(scan.android, isLoading: scan.isLoadingAndroid)
        case .androidSDK: StatusText.androidSDK(scan.android, isLoading: scan.isLoadingAndroid)
        case .gradleCaches: StatusText.gradleCaches(scan.android, isLoading: scan.isLoadingAndroid)
        case .worktrees: StatusText.worktrees(scan.extras?.worktrees, isLoading: scan.isLoadingExtras)
        }
    }

    // MARK: The window

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

    // MARK: Xcodes, runtimes, worktrees and Android

    /// The runtime waiting on the removal sheet.
    var runtimeToRemove: SimulatorRuntime?
    private(set) var isRemovingRuntime = false
    var runtimeRemovalError: String?

    var staleDays: Int {
        self.preferences.staleDays
    }

    /// The selected runtime, or the first flagged one, or the first.
    var currentRuntime: SimulatorRuntime? {
        let runtimes = self.scan.extras?.runtimes ?? []
        return runtimes.first { $0.id == self.selectedRuntime }
            ?? runtimes.first { $0.flagReason(staleDays: self.staleDays) != nil }
            ?? runtimes.first
    }

    /// What the current Android screen lists, in the order it shows them.
    var androidEntries: [AndroidEntry] {
        guard let android = self.scan.android else { return [] }
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
        let xcodes = self.scan.extras?.xcodes ?? []
        return xcodes.first { $0.path == self.selectedXcode } ?? xcodes.first { $0.isSelected } ?? xcodes.first
    }

    /// The selected worktree, or the first with nothing to lose, or the first.
    var currentWorktree: GitWorktree? {
        let worktrees = self.scan.extras?.worktrees ?? []
        return worktrees.first { $0.path == self.selectedWorktree }
            ?? worktrees.first { $0.keptBecause == nil }
            ?? worktrees.first
    }

    /// Removes the runtime on the sheet through simctl, then lists runtimes again.
    func removeRuntime(_ runtime: SimulatorRuntime) async {
        guard !self.isRemovingRuntime else { return }
        self.isRemovingRuntime = true
        self.runtimeRemovalError = nil
        let removed = await self.scan.removeRuntime(runtime)
        self.isRemovingRuntime = false
        if removed {
            self.runtimeToRemove = nil
            self.selectedRuntime = nil
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
        guard !self.isRemovingWorktree else { return }
        self.isRemovingWorktree = true
        self.worktreeRemovalError = nil
        let removed = await self.scan.removeWorktree(worktree)
        self.isRemovingWorktree = false
        if removed {
            self.worktreeToRemove = nil
            self.selectedWorktree = nil
        } else {
            self.worktreeRemovalError = "Git didn't remove it. It may have changed since it was listed, or hold a "
                + "submodule; run the command in Terminal to see why."
        }
    }

    // MARK: Without scanning, for tests and screenshots

    #if DEBUG
    /// Shows results as if a scan had just measured them.
    func showResults(_ results: [ItemResult]) {
        self.scan.showResults(results)
        self.selection = self.scan.tally.ordered.first?.item
    }

    /// Puts the window back to the moment `measured` items were done.
    func rewindScan(toMeasured measured: Int) {
        self.scan.rewindScan(toMeasured: measured)
        self.marks.reset()
    }
    #endif
}

/// Opens Finder on paths, selected.
enum Finder {
    static func reveal(_ paths: [String]) {
        let urls = paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

extension View {
    /// Puts the app's models in the environment, for a scene, a sheet or a test.
    func environment(models app: AppModel) -> some View {
        self.environment(app)
            .environment(app.scan)
            .environment(app.marks)
            .environment(app.runningApps)
            .environment(app.cleaning)
    }
}
