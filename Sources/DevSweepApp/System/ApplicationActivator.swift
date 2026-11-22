import AppKit

/// The app as `NSApplication` brings it to the front, and quits it as
/// choosing Quit would.
@MainActor
struct ApplicationActivator: AppActivating {
    func activate() {
        NSApplication.shared.activate()
    }

    func terminate() {
        NSApplication.shared.terminate(nil)
    }
}
