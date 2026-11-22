import AppKit

/// Says when launching finishes, and whether macOS opened the app at login,
/// from the open-application event AppKit is handling as it finishes.
@MainActor
final class LaunchObserver {
    /// Called once, as launching finishes: true when macOS opened the app
    /// at login.
    var onLaunch: (@MainActor (_ atLogin: Bool) -> Void)?
    private var observer: (any NSObjectProtocol)?

    init() {
        // Delivered at once, on the main thread that posts it: the event is
        // current only while AppKit handles it.
        self.observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: nil)
        { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onLaunch?(LaunchEvent.isAtLogin(NSAppleEventManager.shared().currentAppleEvent))
            }
        }
    }
}
