import DevSweepKit
import Foundation
import Synchronization
import Testing
@testable import DevSweepApp

/// Keeps what would have been posted.
final class RecordingPoster: NotificationPoster {
    let posted = Mutex<[String]>([])
    func post(title: String, body: String) async { self.posted.withLock { $0.append(title) } }
}

@MainActor
@Suite("Daily scan and growth")
struct AppCoordinatorTests {
    @Test
    func `A scan is due a day after the last one, and never before a first`() {
        let last = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!ScanSchedule.isDue(lastScan: nil, now: last))
        #expect(!ScanSchedule.isDue(lastScan: last, now: last.addingTimeInterval(23 * 3600)))
        #expect(ScanSchedule.isDue(lastScan: last, now: last.addingTimeInterval(24 * 3600)))
    }

    @Test
    func `DerivedData growth past the threshold since the last scan is worth a notification`() {
        let gigabyte: Int64 = 1024 * 1024
        #expect(GrowthCheck.derivedData(
            previousKilobytes: nil,
            currentKilobytes: 90 * gigabyte,
            thresholdGigabytes: 20) == nil)
        #expect(GrowthCheck.derivedData(
            previousKilobytes: 40 * gigabyte,
            currentKilobytes: 60 * gigabyte,
            thresholdGigabytes: 20) == nil)
        let alert = GrowthCheck.derivedData(
            previousKilobytes: 40 * gigabyte,
            currentKilobytes: 61 * gigabyte,
            thresholdGigabytes: 20)
        #expect(alert?.title == "DerivedData grew by \(SizeText.of(kilobytes: 21 * gigabyte))")
        #expect(alert?.body.contains(SizeText.of(kilobytes: 40 * gigabyte)) == true)
        #expect(GrowthCheck.derivedData(
            previousKilobytes: 60 * gigabyte,
            currentKilobytes: 10 * gigabyte,
            thresholdGigabytes: 1) == nil)
    }

    @Test
    func `the threshold is a preference, 20 GB unless changed`() {
        let storage = InMemoryPreferencesStore()
        #expect(Preferences(storage: storage).derivedDataGrowthGigabytes == 20)
        Preferences(storage: storage).derivedDataGrowthGigabytes = 35
        #expect(Preferences(storage: storage).derivedDataGrowthGigabytes == 35)
    }

    @Test
    func `A tick a day after the last scan starts the next one, and a small change posts nothing`() async {
        let home = TemporaryHome()
        write(64, to: "\(home.path)/Library/Developer/Xcode/DerivedData/App-abc")
        let poster = RecordingPoster()
        let app = scanningApp(home: home, notifier: poster)
        await finishScan(app)
        #expect(!app.scan.isScanning)

        app.tick(now: Date().addingTimeInterval(3600))
        #expect(!app.scan.isScanning)
        app.tick(now: Date().addingTimeInterval(25 * 3600))
        #expect(app.scan.isScanning)
        app.scan.stopScan()
        #expect(poster.posted.withLock { $0 }.isEmpty)
    }
}
