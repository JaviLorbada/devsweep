import Testing
@testable import DevSweepApp

@MainActor
@Suite("Menu bar panel")
struct MenuBarViewModelTests {
    @Test
    func `Scan Now starts a scan, and says so while it runs`() {
        let scan = FakeScanning()
        let menuBar = MenuBarViewModel(scan: scan, updates: FakeUpdateChecking(), app: FakeActivator())
        #expect(menuBar.scanTitle == "Scan Now")
        #expect(menuBar.canScanNow)
        menuBar.scanNow()
        #expect(scan.scans == 1)

        scan.isScanning = true
        #expect(menuBar.scanTitle == "Scanning…")
        #expect(!menuBar.canScanNow)
        menuBar.scanNow()
        #expect(scan.scans == 1, "a scan already runs")
    }

    @Test
    func `Scan Now waits while a clean runs, and does nothing without a home to scan`() {
        let scan = FakeScanning()
        let menuBar = MenuBarViewModel(scan: scan, updates: FakeUpdateChecking(), app: FakeActivator())
        scan.isCleaning = true
        #expect(!menuBar.canScanNow)
        menuBar.scanNow()
        scan.isCleaning = false
        scan.canScan = false
        #expect(!menuBar.canScanNow)
        menuBar.scanNow()
        #expect(scan.scans == 0)
    }

    @Test
    func `Check for Updates… asks the updates, and waits while a check runs`() {
        let updates = FakeUpdateChecking()
        let menuBar = MenuBarViewModel(scan: FakeScanning(), updates: updates, app: FakeActivator())
        #expect(menuBar.showsCheckForUpdates)
        #expect(menuBar.canCheckForUpdates)
        menuBar.checkForUpdates()
        #expect(updates.checks == 1)
        updates.canCheck = false
        #expect(!menuBar.canCheckForUpdates)
    }

    @Test
    func `a build that doesn't update itself shows no Check for Updates…`() {
        let updates = FakeUpdateChecking()
        updates.isAvailable = false
        let menuBar = MenuBarViewModel(scan: FakeScanning(), updates: updates, app: FakeActivator())
        #expect(!menuBar.showsCheckForUpdates)
    }

    @Test
    func `an update that waits shows a dot and New Version Available…, which brings it up`() {
        let updates = FakeUpdateChecking()
        let menuBar = MenuBarViewModel(scan: FakeScanning(), updates: updates, app: FakeActivator())
        #expect(!menuBar.showsUpdateAvailable)

        updates.isUpdateWaiting = true
        #expect(menuBar.showsUpdateAvailable)
        menuBar.checkForUpdates()
        #expect(updates.checks == 1, "Sparkle brings the waiting update to the front")
    }

    @Test
    func `opening the window or Settings brings the app to the front, and Quit quits it`() {
        let app = FakeActivator()
        let menuBar = MenuBarViewModel(scan: FakeScanning(), updates: FakeUpdateChecking(), app: app)
        menuBar.bringToFront()
        #expect(app.activations == 1)
        #expect(!app.terminated)
        menuBar.quit()
        #expect(app.terminated)
    }
}
