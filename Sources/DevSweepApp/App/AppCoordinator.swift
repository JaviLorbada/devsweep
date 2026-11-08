import AppKit
import DevSweepKit
import SwiftUI

/// The top of the app: builds the dependencies, the shared models and the
/// view models, and wires what one model's events set off in the others.
///
/// - A scan starting clears the marks and the last parts cleans.
/// - A scan's items all measured tick the biggest and, unless it was
///   stopped, select the first.
/// - A scan finished checks DerivedData's growth and may notify.
/// - Every half minute: the clock, the free space, and the daily scan.
///
/// It is the one place that names the models' classes: they take each other
/// through the protocols in `Protocols`, and it hands each the real one.
/// Views never see it; the scenes put its models in the environment with
/// `environment(models:)`.
@MainActor
final class AppCoordinator {
    let preferences: Preferences
    let scan: ScanModel
    let marks: MarksModel
    let runningApps: RunningAppsModel
    let cleaning: CleaningModel
    let window: WindowViewModel
    let overview: OverviewViewModel
    let xcodes: XcodesViewModel
    let runtimes: RuntimesViewModel
    let worktrees: WorktreesViewModel
    let android: AndroidViewModel
    private let notifier: NotificationPoster

    /// Everything is live unless a test says otherwise.
    /// - Parameters:
    ///   - store: where the last scan is kept; the home's own file when nil.
    ///   - dependencies: the kit's side effects; `Dependencies.live` when nil.
    ///   - quitter: quits Xcode and Simulator; as choosing Quit would when nil.
    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        store: (any ScanMemoryStore)? = nil,
        preferences: Preferences? = nil,
        notifier: NotificationPoster = UserNotificationPoster(),
        dependencies: Dependencies? = nil,
        quitter: (any AppQuitting)? = nil)
    {
        let preferences = preferences ?? Preferences()
        self.preferences = preferences
        self.notifier = notifier
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

        // The shared models, each on the ones it needs.
        let scan = ScanModel(
            environment: environment,
            store: store,
            preferences: preferences,
            dependencies: dependencies)
        let marks = MarksModel(scan: scan)
        let runningApps = RunningAppsModel(
            checker: dependencies.tools.runningApps,
            quitter: quitter ?? WorkspaceAppQuitter())
        let cleaning = CleaningModel(
            scan: scan,
            marks: marks,
            apps: runningApps,
            moveToTrash: preferences.moveToTrash)
        self.scan = scan
        self.marks = marks
        self.runningApps = runningApps
        self.cleaning = cleaning

        // The view models, on the shared models.
        let window = WindowViewModel()
        self.window = window
        self.overview = OverviewViewModel(window: window, scan: scan, cleaning: cleaning, apps: runningApps)
        self.xcodes = XcodesViewModel(scan: scan)
        self.runtimes = RuntimesViewModel(scan: scan, preferences: preferences)
        self.worktrees = WorktreesViewModel(scan: scan)
        self.android = AndroidViewModel(window: window, scan: scan, preferences: preferences)

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
            if !stopped { self.overview.selectFirstIfNone() }
        }
        self.scan.onFinished = { [weak self] in
            self?.checkGrowth()
        }
    }

    /// The window is up: a scan, when the preferences ask for one at launch;
    /// in a development build, then a screenshot or a debug run when asked.
    func windowAppeared() async {
        #if DEBUG
        if DebugLaunch.isRequested { FileHandle.standardError.write(Data("debug launch: window appeared\n".utf8)) }
        #endif
        if self.preferences.scanOnLaunch { self.scan.scan() }
        #if DEBUG
        await Snapshotter.runIfAsked(self)
        await DebugLaunch.run(self)
        #endif
    }

    /// Every half minute: the clock for "3 minutes ago", the free space for
    /// the menu bar, and a scan once the last one is a day old. Not while a
    /// clean runs or waits on an answer: the scan would take its rows.
    func tick(now: Date) {
        self.scan.tick(now: now)
        if ScanSchedule.isDue(lastScan: self.scan.lastScan, now: now), !self.scan.isScanning,
           !self.scan.isCleaning, self.cleaning.pendingClean == nil
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
        let notifier = self.notifier
        Task { await notifier.post(title: alert.title, body: alert.body) }
    }

    // MARK: Without scanning, for tests and screenshots

    #if DEBUG
    /// Shows results as if a scan had just measured them.
    func showResults(_ results: [ItemResult]) {
        self.scan.showResults(results)
        self.overview.select(self.scan.tally.ordered.first?.item)
    }

    /// Puts the window back to the moment `measured` items were done.
    func rewindScan(toMeasured measured: Int) {
        self.scan.rewindScan(toMeasured: measured)
        self.marks.reset()
    }
    #endif
}

extension View {
    /// Puts the app's models in the environment, for a scene or a test.
    /// Each view then takes only the ones it reads.
    func environment(models app: AppCoordinator) -> some View {
        self.environment(app.preferences)
            .environment(app.scan)
            .environment(app.marks)
            .environment(app.runningApps)
            .environment(app.cleaning)
            .environment(app.window)
            .environment(app.overview)
            .environment(app.xcodes)
            .environment(app.runtimes)
            .environment(app.worktrees)
            .environment(app.android)
    }
}
