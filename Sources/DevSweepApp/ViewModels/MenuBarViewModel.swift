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

    func checkForUpdates() {
        self.updates.checkForUpdates()
    }

    /// An update the daily check found that waits: its row heads the
    /// panel's items, while the menu bar item shows a dot.
    var waitingUpdate: WaitingUpdate? {
        self.updates.waitingUpdate
    }

    var showsUpdateDot: Bool {
        self.waitingUpdate != nil
    }

    /// The waiting update's row: Sparkle brings a found update to the front,
    /// and a downloaded one installs and relaunches the app.
    func chooseWaitingUpdate() {
        switch self.waitingUpdate {
        case .available:
            self.updates.checkForUpdates()
        case .ready:
            self.updates.installUpdate()
        case nil:
            break
        }
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
