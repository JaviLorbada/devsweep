#if DEBUG
import Foundation

/// Shows the update controls as a build with a feed does, and checks
/// nothing: what screenshots and debug runs use, so they show the released
/// app's menus and Settings without asking the network. With
/// `DEVSWEEP_UPDATE=waiting`, an update waits from launch, as after a
/// scheduled check found one: the menu bar item's dot and its panel's row.
@MainActor
final class StandInUpdater: AppUpdating {
    var canCheckForUpdates = true
    var checksAutomatically = false
    var downloadsAutomatically = false
    let isUpdateWaiting = ProcessInfo.processInfo.environment["DEVSWEEP_UPDATE"] == "waiting"
    var onChange: (@MainActor () -> Void)?

    func checkForUpdates() {}
}
#endif
