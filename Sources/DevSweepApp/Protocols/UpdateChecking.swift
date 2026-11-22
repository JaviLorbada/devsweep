/// Check for Updates… as a button outside the app menu shows it: whether
/// this build updates itself, whether a check can start now, and starting
/// one.
///
/// `UpdatesModel` conforms. `MenuBarViewModel` takes it, so its tests need
/// no updater.
@MainActor
protocol UpdateChecking: AnyObject {
    var isAvailable: Bool { get }
    var canCheck: Bool { get }
    func checkForUpdates()
}
