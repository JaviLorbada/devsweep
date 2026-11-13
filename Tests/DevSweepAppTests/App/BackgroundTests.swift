import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

/// When the next scan is due, and when DerivedData's growth is worth a
/// notification: plain values the coordinator's tick and a scan's end use.
@MainActor
@Suite("Daily scan and growth")
struct BackgroundTests {
    @Test
    func `A scan is due a day after the last one, and never before a first`() {
        let last = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!ScanSchedule.isDue(lastScan: nil, now: last))
        #expect(!ScanSchedule.isDue(lastScan: last, now: last.addingTimeInterval(23 * 3600)))
        #expect(ScanSchedule.isDue(lastScan: last, now: last.addingTimeInterval(24 * 3600)))
    }

    @Test
    func `DerivedData growth past the threshold since the last scan is worth a notification`() {
        /// Gigabytes as the app writes them, in the kit's 1024-byte kilobytes.
        func gigabytes(_ count: Int64) -> Int64 { count * 1_000_000_000 / 1024 }
        #expect(GrowthCheck.derivedData(
            previousKilobytes: nil,
            currentKilobytes: gigabytes(90),
            thresholdGigabytes: 20) == nil)
        #expect(GrowthCheck.derivedData(
            previousKilobytes: gigabytes(40),
            currentKilobytes: gigabytes(60),
            thresholdGigabytes: 20) == nil)
        let alert = GrowthCheck.derivedData(
            previousKilobytes: gigabytes(40),
            currentKilobytes: gigabytes(61),
            thresholdGigabytes: 20)
        #expect(alert?.title == "DerivedData grew by 21.0 GB")
        #expect(alert?.body == "It holds 61.0 GB now, up from 40.0 GB at the last scan. Open DevSweep to clean it.")
        #expect(GrowthCheck.derivedData(
            previousKilobytes: gigabytes(60),
            currentKilobytes: gigabytes(10),
            thresholdGigabytes: 1) == nil)
    }

    @Test
    func `the threshold is a preference, 20 GB unless changed`() {
        let storage = InMemoryPreferencesStore()
        #expect(Preferences(storage: storage).derivedDataGrowthGigabytes == 20)
        Preferences(storage: storage).derivedDataGrowthGigabytes = 35
        #expect(Preferences(storage: storage).derivedDataGrowthGigabytes == 35)
    }
}
