/// Check for Updates… as a button outside the app menu shows it: whether
/// this build updates itself, whether a check can start now, starting one,
/// and whether an update a scheduled check found waits for the person.
///
/// `UpdatesModel` conforms. `MenuBarViewModel` takes it, so its tests need
/// no updater.
@MainActor
protocol UpdateChecking: AnyObject {
    var isAvailable: Bool { get }
    var canCheck: Bool { get }
    var isUpdateWaiting: Bool { get }
    func checkForUpdates()
}
