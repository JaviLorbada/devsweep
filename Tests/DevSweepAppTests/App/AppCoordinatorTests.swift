import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

/// The coordinator builds the real models and wires one's events to the
/// others, so its tests build the whole app on a fake home and check that
/// wiring. Each model's own behaviour is tested in its own file, with fakes.
@MainActor
@Suite("Coordinator")
struct AppCoordinatorTests {
    @Test
    func `a finished scan ticks the three biggest and selects the biggest`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let app = await scannedApp(home: home)
        #expect(app.scan.tally.live.count == 4)
        #expect(app.marks.marked == [.derivedData, .swiftpmCache, .toolCaches])
        #expect(app.overview.selection == .derivedData)
    }

    @Test
    func `a new scan starts with nothing ticked`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let app = await scannedApp(home: home)
        app.marks.markAll()
        app.scan.scan()
        #expect(app.marks.marked.isEmpty)
        app.scan.stopScan()
    }

    @Test
    func `cleaning starts out the way the preferences say`() {
        let storage = InMemoryPreferencesStore()
        storage.set(false, forKey: Preferences.Key.moveToTrash)
        let home = TemporaryHome()
        let app = AppCoordinator(
            environment: testEnvironment(home: home),
            store: InMemoryScanStore(),
            preferences: Preferences(storage: storage),
            notifier: SilentNotificationPoster(),
            dependencies: Dependencies(tools: .unavailable))
        #expect(!app.cleaning.moveToTrash)
    }

    @Test
    func `the app updates itself only with the updater it is handed, and a test's never checks`() {
        let home = TemporaryHome()
        #expect(!scanningApp(home: home).updates.isAvailable)

        let updater = FakeUpdater()
        let app = AppCoordinator(
            environment: testEnvironment(home: home),
            store: InMemoryScanStore(),
            preferences: Preferences(storage: InMemoryPreferencesStore()),
            notifier: SilentNotificationPoster(),
            updater: updater,
            dependencies: Dependencies(tools: .unavailable))
        #expect(app.updates.isAvailable)
        app.updates.checkForUpdates()
        #expect(updater.checks == 1)
    }

    @Test
    func `the daily scan waits while a clean's question is open`() async {
        let home = TemporaryHome()
        write(64, to: "\(home.path)/Library/Developer/Xcode/DerivedData/Atlas-abc")
        let app = await scannedApp(home: home, apps: FakeDeveloperApps(running: [.xcode]))
        await app.cleaning.requestClean([.derivedData])
        #expect(app.cleaning.pendingClean != nil)

        let tomorrow = Date().addingTimeInterval(25 * 3600)
        app.tick(now: tomorrow)
        #expect(!app.scan.isScanning)
        app.cleaning.dismissPendingClean()
        app.tick(now: tomorrow)
        #expect(app.scan.isScanning)
        app.scan.stopScan()
    }

    @Test
    func `A tick a day after the last scan starts the next one, and a small change posts nothing`() async {
        let home = TemporaryHome()
        write(64, to: "\(home.path)/Library/Developer/Xcode/DerivedData/App-abc")
        let poster = RecordingPoster()
        let app = scanningApp(home: home, notifier: poster)
        await finishScan(app.scan)
        #expect(!app.scan.isScanning)

        app.tick(now: Date().addingTimeInterval(3600))
        #expect(!app.scan.isScanning)
        app.tick(now: Date().addingTimeInterval(25 * 3600))
        #expect(app.scan.isScanning)
        app.scan.stopScan()
        #expect(poster.posted.withLock { $0 }.isEmpty)
    }
}
