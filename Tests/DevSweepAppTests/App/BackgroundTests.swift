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
}
