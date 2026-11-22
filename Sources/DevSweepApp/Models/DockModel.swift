import Observation

/// Whether the app is in the Dock and the app switcher, kept to what
/// `DockIcon` says as launching finishes, as the window and Settings open
/// and close, and as either setting changes. The scenes say when a window
/// opens and closes.
@MainActor
final class DockModel {
    /// The windows that bring the icon back while they are open.
    enum Window {
        case main
        case settings
    }

    /// Whether the icon shows. A bundle starts out a regular app, until
    /// launching finishes.
    private(set) var isIconShown = true
    private var openWindows: Set<Window> = []
    private let preferences: Preferences
    private let dockIcon: any DockIconShowing

    init(preferences: Preferences, dockIcon: any DockIconShowing) {
        self.preferences = preferences
        self.dockIcon = dockIcon
        self.followPreferences()
    }

    /// Launching finished, with the window on its way or, at login, none.
    /// Sets the icon even when it is unchanged: run from a plain executable,
    /// the app has no bundle telling macOS it is a regular app with a Dock
    /// icon and a menu bar.
    func launched(withWindow: Bool) {
        let shown = self.isShown(windowOpen: withWindow || !self.openWindows.isEmpty)
        self.isIconShown = shown
        self.dockIcon.setShown(shown)
    }

    func opened(_ window: Window) {
        self.openWindows.insert(window)
        self.update()
    }

    func closed(_ window: Window) {
        self.openWindows.remove(window)
        self.update()
    }

    private func update() {
        let shown = self.isShown(windowOpen: !self.openWindows.isEmpty)
        guard shown != self.isIconShown else {
            return
        }
        self.isIconShown = shown
        self.dockIcon.setShown(shown)
    }

    private func isShown(windowOpen: Bool) -> Bool {
        DockIcon.isShown(
            showInDock: self.preferences.showInDock,
            showInMenuBar: self.preferences.showInMenuBar,
            windowOpen: windowOpen)
    }

    /// Updates whenever either setting changes, in Settings or not: the
    /// menu bar item dragged out of the menu bar turns its setting off, and
    /// with every window closed the icon has to come back.
    private func followPreferences() {
        withObservationTracking {
            _ = self.preferences.showInDock
            _ = self.preferences.showInMenuBar
        } onChange: { [weak self] in
            // Called as the setting is about to change: the update reads it
            // once it has.
            Task { @MainActor in
                self?.update()
                self?.followPreferences()
            }
        }
    }
}
