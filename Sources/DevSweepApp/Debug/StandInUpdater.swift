#if DEBUG
/// Shows the update controls as a build with a feed does, and checks
/// nothing: what screenshots and debug runs use, so they show the released
/// app's menus and Settings without asking the network.
@MainActor
final class StandInUpdater: AppUpdating {
    var canCheckForUpdates = true
    var checksAutomatically = false
    var downloadsAutomatically = false
    var onChange: (@MainActor () -> Void)?

    func checkForUpdates() {}
}
#endif
