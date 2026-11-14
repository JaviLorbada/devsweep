import Observation

/// Updates, as the app menu and Settings show them: whether this build
/// updates itself at all, Check for Updates…, and the automatic checks.
/// Sparkle does the work and keeps the settings; this mirrors them, and
/// follows them when Sparkle's own question changes them.
@MainActor
@Observable
final class UpdatesModel {
    /// Whether this build updates itself. A build without a feed, such as a
    /// development build, doesn't, and shows no update controls.
    let isAvailable: Bool
    /// Whether Check for Updates… can start a check now.
    private(set) var canCheck = false
    /// Whether it looks once a day on its own.
    private(set) var checksAutomatically = false
    /// Whether an update it finds installs without asking. Never without
    /// the automatic checks, which find it.
    private(set) var downloadsAutomatically = false
    @ObservationIgnored private let updater: (any AppUpdating)?

    /// - Parameter updater: Sparkle, live; nil in a build without a feed,
    ///   and in tests unless they hand it a fake.
    init(updater: (any AppUpdating)?) {
        self.updater = updater
        self.isAvailable = updater != nil
        self.refresh()
        updater?.onChange = { [weak self] in self?.refresh() }
    }

    /// Looks for an update now, in Sparkle's windows.
    func checkForUpdates() {
        guard self.canCheck else { return }
        self.updater?.checkForUpdates()
    }

    /// Turns the daily check on or off, as the person chose in Settings.
    func setChecksAutomatically(_ checks: Bool) {
        self.updater?.checksAutomatically = checks
        self.refresh()
    }

    /// Turns installing what the daily check finds on or off.
    func setDownloadsAutomatically(_ downloads: Bool) {
        self.updater?.downloadsAutomatically = downloads
        self.refresh()
    }

    private func refresh() {
        guard let updater = self.updater else { return }
        self.canCheck = updater.canCheckForUpdates
        self.checksAutomatically = updater.checksAutomatically
        self.downloadsAutomatically = updater.checksAutomatically && updater.downloadsAutomatically
    }
}
