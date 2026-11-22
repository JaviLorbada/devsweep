import AppKit

/// The app as `NSApplication` brings it to the front, and quits it as
/// choosing Quit would.
struct ApplicationActivator: AppActivating {
    @MainActor
    func activate() {
        NSApplication.shared.activate()
    }

    @MainActor
    func terminate() {
        NSApplication.shared.terminate(nil)
    }
}
