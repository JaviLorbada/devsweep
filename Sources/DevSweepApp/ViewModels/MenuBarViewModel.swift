import Observation

/// The menu bar item's own state and actions, and its panel's: an update
/// that waits, Scan Now, Check for Updates…, bringing the app to the front
/// once the window, Settings or About opens, and Quit. What the last scan
/// found the panel reads from the scan as it is, through `Tally` and
/// `StatusText`.
@MainActor
@Observable
final class MenuBarViewModel {
    private let scan: any Scanning
    private let updates: any UpdateChecking
    private let app: any AppActivating

    init(scan: any Scanning, updates: any UpdateChecking, app: any AppActivating) {
        self.scan = scan
        self.updates = updates
        self.app = app
    }

    var scanTitle: String {
        self.scan.isScanning ? "Scanning…" : "Scan Now"
    }

    /// Not while a scan or a clean runs, nor without a home to scan.
    var canScanNow: Bool {
        !self.scan.isScanning && !self.scan.isCleaning && self.scan.canScan
    }

    func scanNow() {
        guard self.canScanNow else {
            return
        }
        self.scan.scan()
    }

    /// Only in a build that updates itself, as in the app menu.
    var showsCheckForUpdates: Bool {
        self.updates.isAvailable
    }

    /// Not while a check is already looking or downloading.
    var canCheckForUpdates: Bool {
        self.updates.canCheck
    }

    /// Also what New Version Available… does: Sparkle brings the update
    /// that waits to the front.
    func checkForUpdates() {
        self.updates.checkForUpdates()
    }

    /// While an update a scheduled check found waits: a dot on the menu bar
    /// item, and New Version Available… above the panel's other items.
    var showsUpdateAvailable: Bool {
        self.updates.isUpdateWaiting
    }

    /// Once the panel has opened the window, Settings or About, which only a
    /// view can, with SwiftUI's actions: with the app out of the Dock, they
    /// would otherwise open behind the app in front.
    func bringToFront() {
        self.app.activate()
    }

    func quit() {
        self.app.terminate()
    }
}
