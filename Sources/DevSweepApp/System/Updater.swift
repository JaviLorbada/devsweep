import Foundation
import Sparkle

/// What updates the app, as `UpdatesModel` sees it: Sparkle, live. Tests
/// hand the model a fake, so no test ever asks the network.
@MainActor
protocol AppUpdating: AnyObject {
    /// Whether a check can start now: not while one is already looking or
    /// downloading in the background.
    var canCheckForUpdates: Bool { get }
    /// Whether it looks once a day on its own. Off until the person says
    /// otherwise, in Settings or when Sparkle asks on the second launch.
    var checksAutomatically: Bool { get set }
    /// Whether an update it finds is downloaded and installed without
    /// asking, the next time the app quits.
    var downloadsAutomatically: Bool { get set }
    /// Called when any of the three changes, here or in Sparkle's own windows.
    var onChange: (@MainActor () -> Void)? { get set }
    /// Looks now, and shows what it finds in Sparkle's windows.
    func checkForUpdates()
}

/// Sparkle's standard updater: its windows for a check and an update, and
/// its settings, which it keeps in the app's defaults. The feed and the key
/// its updates are signed with come from the Info.plist that
/// `Scripts/package_app.sh` writes.
@MainActor
final class SparkleUpdater: AppUpdating {
    var onChange: (@MainActor () -> Void)?
    private let controller: SPUStandardUpdaterController
    private var observations: [NSKeyValueObservation] = []

    /// The updater for this build, started; nil in a build without a feed,
    /// such as a development build or the app run from the build folder,
    /// which then shows no update controls.
    static func forThisBuild(_ bundle: Bundle = .main) -> SparkleUpdater? {
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String, !feed.isEmpty else {
            return nil
        }
        return SparkleUpdater()
    }

    private init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil)
        let updater = self.controller.updater
        // Sparkle changes these on the main thread, and says so with KVO.
        let changed: @Sendable (SPUUpdater, NSKeyValueObservedChange<Bool>) -> Void = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        self.observations = [
            updater.observe(\.canCheckForUpdates, changeHandler: changed),
            updater.observe(\.automaticallyChecksForUpdates, changeHandler: changed),
            updater.observe(\.automaticallyDownloadsUpdates, changeHandler: changed),
        ]
    }

    var canCheckForUpdates: Bool {
        self.controller.updater.canCheckForUpdates
    }

    var checksAutomatically: Bool {
        get { self.controller.updater.automaticallyChecksForUpdates }
        set { self.controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var downloadsAutomatically: Bool {
        get { self.controller.updater.automaticallyDownloadsUpdates }
        set { self.controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    func checkForUpdates() {
        self.controller.checkForUpdates(nil)
    }
}
