import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

@Suite("Status text")
struct StatusTextTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `the status line says what the scan found, what is open and what this session cleaned`() {
        let facts = StatusText.Facts(measured: 11, items: 11, lastScan: self.now, now: self.now)
        #expect(StatusText.overview(facts, runningApps: [], trashedKilobytes: 0, deletedKilobytes: 0)
            == "Scanned just now, 11 items. Xcode and Simulator are closed.")
        let gigabyte: Int64 = 1024 * 1024
        #expect(StatusText.overview(facts, runningApps: [.xcode], trashedKilobytes: gigabyte, deletedKilobytes: 0)
            == "Scanned just now, 11 items. Xcode is open. \(SizeText.of(kilobytes: gigabyte)) moved to Trash "
            + "this session.")
        #expect(StatusText.overview(facts, runningApps: [], trashedKilobytes: 0, deletedKilobytes: gigabyte)
            .hasSuffix("\(SizeText.of(kilobytes: gigabyte)) deleted this session."))
    }

    @Test
    func `while scanning it counts, after the last launch's date while that is still shown`() {
        var facts = StatusText.Facts(isScanning: true, measured: 3, items: 11, now: self.now)
        #expect(StatusText.overview(facts, runningApps: [], trashedKilobytes: 0, deletedKilobytes: 0)
            == "Scanning, 3 of 11 items measured.")
        facts.previousScanDate = self.now.addingTimeInterval(-30)
        facts.showsPrevious = true
        #expect(StatusText.overview(facts, runningApps: [], trashedKilobytes: 0, deletedKilobytes: 0)
            == "Last scanned just now. Scanning, 3 of 11 items measured.")
        #expect(StatusText.menuBar(facts) == "Scanning, 3 of 11 items measured.")
    }

    @Test
    func `a stopped scan, a startup error and no scan at all each say so`() {
        let stopped = StatusText.Facts(measured: 4, items: 11, notMeasured: 7, lastScan: self.now, now: self.now)
        #expect(StatusText.overview(stopped, runningApps: [.simulator], trashedKilobytes: 0, deletedKilobytes: 0)
            == "Stopped after 4 of 11 items. Simulator is open.")
        let broken = StatusText.Facts(startupError: "HOME is not set.")
        #expect(StatusText.overview(broken, runningApps: [], trashedKilobytes: 0, deletedKilobytes: 0)
            == "HOME is not set.")
        #expect(StatusText.overview(StatusText.Facts(), runningApps: [], trashedKilobytes: 0, deletedKilobytes: 0)
            == "Not scanned yet.")
        #expect(StatusText.menuBar(StatusText.Facts()) == "Not scanned yet.")
        #expect(StatusText.menuBar(StatusText.Facts(lastScan: self.now, now: self.now))
            == "Last scanned just now. Scans again a day later while DevSweep runs.")
    }

    @Test
    func `each listing's subtitle sums it, or says it is being listed`() {
        let runtimes = sampleExtras.runtimes
        #expect(StatusText.runtimes(runtimes, isLoading: false)
            == "\(SizeText.of(kilobytes: sampleExtras.runtimesKilobytes)) in 3 runtimes. DevSweep never removes "
            + "these on its own.")
        #expect(StatusText.runtimes(nil, isLoading: true) == "Listing runtimes")
        #expect(StatusText.runtimes(nil, isLoading: false).isEmpty)
        #expect(StatusText.xcodes(Array(sampleExtras.xcodes.prefix(1)), isLoading: false)
            == "\(SizeText.of(kilobytes: 12_582_912)) in 1 Xcode. DevSweep never removes these.")
        #expect(StatusText.androidStudios(sampleAndroid, isLoading: false)
            == "\(SizeText.of(kilobytes: 3_500_000)) in 1 install. DevSweep never removes these.")
        #expect(StatusText.androidSDK(nil, isLoading: true) == "Listing the SDK and emulators")
        #expect(StatusText.gradleCaches(sampleAndroid, isLoading: false)
            == "\(SizeText.of(kilobytes: 4_000_000)) in ~/.gradle. DevSweep never removes these.")
        #expect(StatusText.worktrees([], isLoading: false) == "Nothing to remove.")
    }
}
