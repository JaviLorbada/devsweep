#if DEBUG
import Foundation

/// Shows the update controls as a build with a feed does, and checks
/// nothing: what screenshots and debug runs use, so they show the released
/// app's menus and Settings without asking the network. With
/// `DEVSWEEP_UPDATE=available` or `ready`, an update waits from launch, as
/// after the daily check found or downloaded one: the menu bar item's dot
/// and its panel's row, which here does nothing.
@MainActor
final class StandInUpdater: AppUpdating {
    var canCheckForUpdates = true
    var checksAutomatically = false
    var downloadsAutomatically = false
    let waitingUpdate = WaitingUpdate(rawValue: ProcessInfo.processInfo.environment["DEVSWEEP_UPDATE"] ?? "")
    var canRemindGently: (@MainActor () -> Bool)?
    var onChange: (@MainActor () -> Void)?

    func checkForUpdates() {}
    func installUpdate() {}
}
#endif
