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
    /// Whether an update a scheduled check found waits for the person, from
    /// when it is found until they look at it or the update ends.
    var isUpdateWaiting: Bool { get }
    /// Called when any of the four above changes, here or in Sparkle's own
    /// windows.
    var onChange: (@MainActor () -> Void)? { get set }
    /// Looks now, and shows what it finds in Sparkle's windows.
    func checkForUpdates()
}

/// Sparkle's standard updater: its windows for a check and an update, and
/// its settings, which it keeps in the app's defaults. The feed and the key
/// its updates are signed with come from the Info.plist that
/// `Scripts/package_app.sh` writes.
@MainActor
final class SparkleUpdater: NSObject, AppUpdating {
    var onChange: (@MainActor () -> Void)?
    private(set) var isUpdateWaiting = false
    /// Made once this is, since this is its user driver's delegate.
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self)
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

    override private init() {
        super.init()
        let updater = self.controller.updater
        // Sparkle changes these on the main thread, and says so with KVO.
        let changed: @Sendable (SPUUpdater, NSKeyValueObservedChange<Bool>) -> Void = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
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
        get {
            self.controller.updater.automaticallyChecksForUpdates
        }
        set {
            self.controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var downloadsAutomatically: Bool {
        get {
            self.controller.updater.automaticallyDownloadsUpdates
        }
        set {
            self.controller.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    func checkForUpdates() {
        self.controller.checkForUpdates(nil)
    }

    private func setUpdateWaiting(_ waiting: Bool) {
        guard waiting != self.isUpdateWaiting else {
            return
        }
        self.isUpdateWaiting = waiting
        self.onChange?()
    }
}

/// An update a scheduled check finds waits for the person, as the menu bar
/// item's dot, until they look at it: Sparkle's window may have opened
/// behind the app in front.
/// Sparkle's standard user driver, which calls these, is on the main actor.
extension SparkleUpdater: @MainActor SPUStandardUserDriverDelegate {
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState)
    {
        // One the person checked for is in front of them already.
        if !state.userInitiated {
            self.setUpdateWaiting(true)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        self.setUpdateWaiting(false)
    }

    func standardUserDriverWillFinishUpdateSession() {
        self.setUpdateWaiting(false)
    }
}
