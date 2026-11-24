/// Check for Updates… as a button outside the app menu shows it: whether
/// this build updates itself, whether a check can start now, starting one,
/// and an update the daily check found waiting for the person, with
/// installing it once it is ready.
///
/// `UpdatesModel` conforms. `MenuBarViewModel` takes it, so its tests need
/// no updater.
@MainActor
protocol UpdateChecking: AnyObject {
    var isAvailable: Bool { get }
    var canCheck: Bool { get }
    var waitingUpdate: WaitingUpdate? { get }
    func checkForUpdates()
    func installUpdate()
}
