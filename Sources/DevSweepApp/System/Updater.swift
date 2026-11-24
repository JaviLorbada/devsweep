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
    /// An update the daily check found that waits for the person: from
    /// when it is found until they look at it, or once downloaded, until it
    /// installs. Nil while none waits.
    var waitingUpdate: WaitingUpdate? { get }
    /// Called when any of the four above changes, here or in Sparkle's own
    /// windows.
    var onChange: (@MainActor () -> Void)? { get set }
    /// Asked when a scheduled check finds an update that Sparkle would show
    /// behind other windows: whether it can wait as a gentle reminder
    /// instead. When this says no, or isn't set, Sparkle shows it.
    var canRemindGently: (@MainActor () -> Bool)? { get set }
    /// Looks now, and shows what it finds in Sparkle's windows.
    func checkForUpdates()
    /// Installs the update that is ready and relaunches the app, as Sparkle's
    /// Install and Relaunch does.
    func installUpdate()
}

/// Sparkle's standard updater: its windows for a check and an update, and
/// its settings, which it keeps in the app's defaults. The feed and the key
/// its updates are signed with come from the Info.plist that
/// `Scripts/package_app.sh` writes.
@MainActor
final class SparkleUpdater: NSObject, AppUpdating {
    var onChange: (@MainActor () -> Void)?
    var canRemindGently: (@MainActor () -> Bool)?
    private(set) var waitingUpdate: WaitingUpdate?
    /// What installs the downloaded update and relaunches the app, once
    /// Sparkle hands it over.
    private var installNow: (() -> Void)?
    /// Made once this is, since this is its delegate and its user driver's.
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
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

    func installUpdate() {
        self.installNow?()
    }

    private func setWaitingUpdate(_ update: WaitingUpdate?) {
        guard update != self.waitingUpdate else {
            return
        }
        self.waitingUpdate = update
        self.onChange?()
    }

    /// Once the person has seen the update Sparkle found, or its session
    /// ends. One that is ready waits until it installs.
    private func clearAvailableUpdate() {
        if self.waitingUpdate == .available {
            self.setWaitingUpdate(nil)
        }
    }
}

/// Sparkle's gentle reminders, for an app that is often in the menu bar
/// alone: an update a scheduled check finds waits as the menu bar item's
/// dot, rather than in a window behind the app in front, until the person
/// looks at it. Sparkle still shows it when it would come to the front, and
/// whenever there is no menu bar item to remind from.
/// Sparkle's standard user driver, which calls these, is on the main actor.
extension SparkleUpdater: @MainActor SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool) -> Bool
    {
        immediateFocus || self.canRemindGently?() != true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState)
    {
        // One the person checked for is in front of them already. Whatever
        // its stage, Sparkle's window says whether it is downloaded, and
        // offers what comes next.
        if !state.userInitiated {
            self.setWaitingUpdate(.available)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        self.clearAvailableUpdate()
    }

    func standardUserDriverWillFinishUpdateSession() {
        self.clearAvailableUpdate()
    }
}

/// With automatic installs on, Sparkle downloads an update without a word,
/// to install when the app quits. While the menu bar item can show it, the
/// update waits there, ready to install now; otherwise Sparkle keeps to its
/// own schedule, and may show it in its window days later.
extension SparkleUpdater: SPUUpdaterDelegate {
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool
    {
        guard self.canRemindGently?() == true else {
            return false
        }
        self.installNow = immediateInstallHandler
        self.setWaitingUpdate(.ready)
        return true
    }
}
