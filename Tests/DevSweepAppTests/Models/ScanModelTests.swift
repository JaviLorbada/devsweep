import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

/// The overview's status line, from the scan's facts alone.
@MainActor
private func statusLine(_ scan: ScanModel) -> String {
    StatusText.overview(scan.statusFacts, runningApps: [], trashedKilobytes: 0, deletedKilobytes: 0)
}

@MainActor
@Suite("Scanning")
struct ScanModelTests {
    @Test
    func `rows go largest first, then the one being measured, then the rest by the last scan's size`() {
        let home = TemporaryHome()
        let scan = makeScan(home: home)
        scan.showResults(sampleResults.filter { scan.scanOrder.contains($0.item) })
        scan.rewindScan(toMeasured: 3)
        let order = scan.scanOrder
        let size = { (item: Item) in sampleResults.first { $0.item == item }?.kilobytes ?? 0 }

        let measured = order.prefix(3).sorted { size($0) > size($1) }
        let waiting = order.dropFirst(4).sorted { size($0) > size($1) }
        #expect(scan.tally.ordered.map(\.item) == measured + [order[3]] + waiting)
        #expect(scan.tally.measuringItems == [order[3]])
        #expect(scan.tally.measuredCount == 3)
        #expect(scan.tally.showsPrevious)
    }

    @Test
    func `the ring weighs each row by what is known of its size`() throws {
        let home = TemporaryHome()
        let scan = makeScan(home: home)
        scan.showResults(sampleResults.filter { scan.scanOrder.contains($0.item) })
        scan.rewindScan(toMeasured: 3)
        let order = scan.scanOrder
        let row = { (index: Int) in try #require(scan.rows[order[index]]) }

        // Measured: its size. Being measured: the count so far. Waiting: the last scan's size.
        #expect(try scan.tally.chartWeight(row(0)) == Double(row(0).kilobytes))
        #expect(try scan.tally.chartWeight(row(3)) == Double(row(3).progressBytes / 1024))
        #expect(try scan.tally.chartWeight(row(5)) == Double(row(5).previous?.kilobytes ?? -1))
    }

    @Test
    func `a stopped scan says how far it got`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let scan = makeScan(home: home)
        scan.scan()
        scan.stopScan()
        await waitUntil { !scan.isScanTaskRunning }
        #expect(!scan.isScanning)
        let notMeasured = scan.scanOrder.filter { scan.rows[$0]?.state == .notMeasured }
        #expect(scan.statusFacts.notMeasured == notMeasured.count)
        if notMeasured.isEmpty {
            #expect(statusLine(scan).hasPrefix("Scanned just now"))
        } else {
            #expect(statusLine(scan)
                .hasPrefix("Stopped after \(scan.tally.measuredCount) of \(scan.scanOrder.count) items."))
        }
    }

    @Test
    func `a scan tells the coordinator it started, its items are measured, and it is all in`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let scan = makeScan(home: home)
        var heard: [String] = []
        scan.onStart = { heard.append("start") }
        scan.onItemsMeasured = { stopped in heard.append(stopped ? "stopped" : "measured") }
        scan.onFinished = { heard.append("finished") }
        await finishScan(scan)
        await waitUntil { heard.count == 3 }
        #expect(heard == ["start", "measured", "finished"])
    }

    @Test
    func `a clean takes the rows, and a scan waits until it gives them back`() {
        let home = TemporaryHome()
        let scan = makeScan(home: home)
        #expect(scan.beginCleaning() != nil)
        #expect(scan.beginCleaning() == nil, "one clean at a time")
        #expect(!scan.canScanOrStop)
        scan.scan()
        #expect(!scan.isScanning)

        scan.endCleaning(warnings: ["Skipped Xcode builds: Xcode is open."])
        #expect(scan.canScanOrStop)
        #expect(scan.warnings == ["Skipped Xcode builds: Xcode is open."])
        scan.scan()
        #expect(scan.isScanning)
        #expect(scan.beginCleaning() == nil, "no clean while scanning")
        scan.stopScan()
    }

    @Test
    func `the preferences apply from the next scan: skipped items leave the rows`() {
        let home = TemporaryHome()
        let preferences = Preferences(storage: InMemoryPreferencesStore())
        let scan = makeScan(home: home, preferences: preferences)
        #expect(scan.scanOrder.contains(.homebrew))
        preferences.skippedItems = [.homebrew]
        #expect(scan.scanOrder.contains(.homebrew), "not before the next scan")
        scan.scan()
        #expect(!scan.scanOrder.contains(.homebrew))
        #expect(scan.engine?.config.skipped == [.homebrew])
        scan.stopScan()
    }
}

@MainActor
@Suite("Remembering the last scan")
struct ScanMemoryTests {
    @Test
    func `A finished scan is shown, dimmed, on the next launch until a new one replaces it`() async {
        let home = TemporaryHome()
        write(64, to: "\(home.path)/Library/Caches/org.swift.swiftpm")
        write(32, to: "\(home.path)/.npm/_cacache")

        let first = makeScan(home: home, store: nil)
        await finishScan(first)
        let total = first.tally.reclaimableKilobytes
        #expect(total >= 96)
        #expect(FileManager.default
            .fileExists(atPath: "\(home.path)/Library/Application Support/DevSweep/last-scan.json"))

        let next = makeScan(home: home, store: nil)
        #expect(statusLine(next).hasPrefix("Last scanned"))
        #expect(next.tally.showsPrevious)
        #expect(next.tally.reclaimableKilobytes == total)
        #expect(next.rows[.swiftpmCache]?.showsPrevious == true)
        #expect(next.rows[.swiftpmCache]?.shownKilobytes == first.rows[.swiftpmCache]?.kilobytes)
        #expect(next.tally.live.isEmpty, "nothing from the last scan can be cleaned")

        await finishScan(next)
        #expect(!next.tally.showsPrevious)
        #expect(next.rows[.swiftpmCache]?.state == .measured)
        #expect(statusLine(next).hasPrefix("Scanned just now"))
    }

    @Test
    func `A scan of another home is not shown`() async throws {
        let home = TemporaryHome(), other = TemporaryHome()
        write(16, to: "\(other.path)/.npm/_cacache")
        await finishScan(makeScan(home: other, store: nil))
        let saved = "\(other.path)/Library/Application Support/DevSweep/last-scan.json"
        let copy = "\(home.path)/Library/Application Support/DevSweep/last-scan.json"
        try FileManager.default.createDirectory(
            atPath: (copy as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: saved, toPath: copy)

        let scan = makeScan(home: home, store: nil)
        #expect(!scan.tally.showsPrevious)
        #expect(statusLine(scan) == "Not scanned yet.")
    }

    @Test
    func `while measuring, an item counts toward the totals`() {
        var row = ScanRow(item: .derivedData)
        row.state = .measuring
        row.progressBytes = 5 * 1024 * 1024
        #expect(row.isCounting)
        #expect(row.shownKilobytes == 5 * 1024)
        row.previous = ItemResult(item: .derivedData, paths: ["/dd"], kilobytes: 900, location: "")
        #expect(row.shownKilobytes == 5 * 1024, "the running count, not the last scan, once it is measuring")
        row.state = .waiting
        #expect(row.showsPrevious)
        #expect(row.shownKilobytes == 900)
    }
}
