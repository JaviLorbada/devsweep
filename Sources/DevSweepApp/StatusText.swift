import DevSweepKit
import Foundation

/// The sentences about the scan: the overview's status line, the menu bar's,
/// and each screen's subtitle. Written from plain facts, so each is checked
/// without a model.
enum StatusText {
    /// What the status lines are written from.
    struct Facts {
        var startupError: String?
        var isScanning = false
        var measured = 0
        var items = 0
        /// Items the scan stopped before reaching.
        var notMeasured = 0
        /// Whether the totals still lean on the last launch's scan.
        var showsPrevious = false
        var lastScan: Date?
        /// When the results on screen came from the last launch's scan.
        var previousScanDate: Date?
        var now = Date()
    }

    /// The overview's status line: what the scan is doing or found, whether
    /// Xcode and Simulator are open, and what this session cleaned.
    static func overview(
        _ facts: Facts,
        runningApps: Set<DeveloperApp>,
        trashedKilobytes: Int64,
        deletedKilobytes: Int64) -> String
    {
        if let startupError = facts.startupError { return startupError }
        if facts.isScanning {
            let progress = "Scanning, \(facts.measured) of \(facts.items) items measured"
            if let previousScanDate = facts.previousScanDate, facts.showsPrevious {
                return "Last scanned \(self.relative(previousScanDate, to: facts.now)). \(progress)."
            }
            // Full stops throughout: the build note can follow.
            return "\(progress)."
        }
        guard let lastScan = facts.lastScan else {
            return facts.previousScanDate
                .map { "Last scanned \(self.relative($0, to: facts.now))." } ?? "Not scanned yet."
        }
        let scanned = facts.notMeasured > 0
            ? "Stopped after \(facts.measured) of \(facts.items) items."
            : "Scanned \(self.relative(lastScan, to: facts.now)), \(facts.items) items."
        var line = "\(scanned) \(self.runningApps(runningApps))"
        if trashedKilobytes > 0 {
            line += " \(SizeText.of(kilobytes: trashedKilobytes)) moved to Trash this session."
        }
        if deletedKilobytes > 0 {
            line += " \(SizeText.of(kilobytes: deletedKilobytes)) deleted this session."
        }
        return line
    }

    /// "Last scanned 3 hours ago." under the menu bar panel's totals, or
    /// what is happening.
    static func menuBar(_ facts: Facts) -> String {
        if facts.isScanning { return "Scanning, \(facts.measured) of \(facts.items) items measured." }
        if let lastScan = facts.lastScan {
            return "Last scanned \(self.relative(lastScan, to: facts.now)). Scans again a day later while "
                + "\(ProductInfo.name) runs."
        }
        if let previousScanDate = facts.previousScanDate {
            return "Last scanned \(self.relative(previousScanDate, to: facts.now))."
        }
        return "Not scanned yet."
    }

    /// "just now", "3 minutes ago", "yesterday".
    static func relative(_ date: Date, to now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func runningApps(_ running: Set<DeveloperApp>) -> String {
        switch (running.contains(.xcode), running.contains(.simulator)) {
        case (false, false): "Xcode and Simulator are closed."
        case (true, false): "Xcode is open."
        case (false, true): "Simulator is open."
        case (true, true): "Xcode and Simulator are open."
        }
    }

    // MARK: Subtitles

    static func runtimes(_ runtimes: [SimulatorRuntime]?, isLoading: Bool) -> String {
        guard let runtimes else { return isLoading ? "Listing runtimes" : "" }
        let count = runtimes.count == 1 ? "1 runtime" : "\(runtimes.count) runtimes"
        let kilobytes = runtimes.reduce(0) { $0 + $1.kilobytes }
        return "\(SizeText.of(kilobytes: kilobytes)) in \(count). \(ProductInfo.name) never removes these on its own."
    }

    static func xcodes(_ xcodes: [InstalledXcode]?, isLoading: Bool) -> String {
        guard let xcodes else { return isLoading ? "Listing Xcodes" : "" }
        let count = xcodes.count == 1 ? "1 Xcode" : "\(xcodes.count) Xcodes"
        let kilobytes = xcodes.reduce(0) { $0 + $1.kilobytes }
        return "\(SizeText.of(kilobytes: kilobytes)) in \(count). \(ProductInfo.name) never removes these."
    }

    static func androidStudios(_ android: AndroidReport?, isLoading: Bool) -> String {
        guard let android else { return isLoading ? "Listing Android Studio" : "" }
        let count = android.studios.count == 1 ? "1 install" : "\(android.studios.count) installs"
        return "\(SizeText.of(kilobytes: android.studiosKilobytes)) in \(count). \(ProductInfo.name) never "
            + "removes these."
    }

    static func androidSDK(_ android: AndroidReport?, isLoading: Bool) -> String {
        guard let android else { return isLoading ? "Listing the SDK and emulators" : "" }
        return "\(SizeText.of(kilobytes: android.sdkKilobytes)) in the SDK and emulators. "
            + "\(ProductInfo.name) never removes these."
    }

    static func gradleCaches(_ android: AndroidReport?, isLoading: Bool) -> String {
        guard let android else { return isLoading ? "Listing Gradle's caches" : "" }
        return "\(SizeText.of(kilobytes: android.gradleCachesKilobytes)) in ~/.gradle. \(ProductInfo.name) "
            + "never removes these."
    }

    static func worktrees(_ worktrees: [GitWorktree]?, isLoading: Bool) -> String {
        guard let worktrees else { return isLoading ? "Listing worktrees" : "" }
        return WorktreeWords.summary(worktrees)
    }
}
