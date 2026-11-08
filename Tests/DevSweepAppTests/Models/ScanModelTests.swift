import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Scanning")
struct ScanModelTests {
    @Test
    func `rows go largest first, then the one being measured, then the rest by the last scan's size`() {
        let home = TemporaryHome()
        let app = makeApp(home: home)
        app.showResults(sampleResults.filter { app.scan.scanOrder.contains($0.item) })
        app.rewindScan(toMeasured: 3)
        let order = app.scan.scanOrder
        let size = { (item: Item) in sampleResults.first { $0.item == item }?.kilobytes ?? 0 }

        let measured = order.prefix(3).sorted { size($0) > size($1) }
        let waiting = order.dropFirst(4).sorted { size($0) > size($1) }
        #expect(app.scan.tally.ordered.map(\.item) == measured + [order[3]] + waiting)
        #expect(app.scan.tally.measuringItems == [order[3]])
        #expect(app.scan.tally.measuredCount == 3)
        #expect(app.scan.tally.showsPrevious)
    }

    @Test
    func `the ring weighs each row by what is known of its size`() throws {
        let home = TemporaryHome()
        let app = makeApp(home: home)
        app.showResults(sampleResults.filter { app.scan.scanOrder.contains($0.item) })
        app.rewindScan(toMeasured: 3)
        let order = app.scan.scanOrder
        let row = { (index: Int) in try #require(app.scan.rows[order[index]]) }

        // Measured: its size. Being measured: the count so far. Waiting: the last scan's size.
        #expect(try app.scan.tally.chartWeight(row(0)) == Double(row(0).kilobytes))
        #expect(try app.scan.tally.chartWeight(row(3)) == Double(row(3).progressBytes / 1024))
        #expect(try app.scan.tally.chartWeight(row(5)) == Double(row(5).previous?.kilobytes ?? -1))
    }

    @Test
    func `a stopped scan says how far it got`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let app = scanningApp(home: home)
        app.scan.scan()
        app.scan.stopScan()
        await waitUntil { !app.scan.isScanTaskRunning }
        #expect(!app.scan.isScanning)
        let notMeasured = app.scan.scanOrder.filter { app.scan.rows[$0]?.state == .notMeasured }
        if notMeasured.isEmpty {
            #expect(app.overview.statusLine.hasPrefix("Scanned just now"))
        } else {
            #expect(app.overview.statusLine
                .hasPrefix("Stopped after \(app.scan.tally.measuredCount) of \(app.scan.scanOrder.count) items."))
        }
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

        let first = scanningApp(home: home)
        await finishScan(first)
        let total = first.scan.tally.reclaimableKilobytes
        #expect(total >= 96)
        #expect(FileManager.default
            .fileExists(atPath: "\(home.path)/Library/Application Support/DevSweep/last-scan.json"))

        let next = scanningApp(home: home)
        #expect(next.overview.statusLine.hasPrefix("Last scanned"))
        #expect(next.scan.tally.showsPrevious)
        #expect(next.scan.tally.reclaimableKilobytes == total)
        #expect(next.scan.rows[.swiftpmCache]?.showsPrevious == true)
        #expect(next.scan.rows[.swiftpmCache]?.shownKilobytes == first.scan.rows[.swiftpmCache]?.kilobytes)
        #expect(next.scan.tally.live.isEmpty, "nothing from the last scan can be cleaned")

        await finishScan(next)
        #expect(!next.scan.tally.showsPrevious)
        #expect(next.scan.rows[.swiftpmCache]?.state == .measured)
        #expect(next.overview.statusLine.hasPrefix("Scanned just now"))
    }

    @Test
    func `A scan of another home is not shown`() async throws {
        let home = TemporaryHome(), other = TemporaryHome()
        write(16, to: "\(other.path)/.npm/_cacache")
        let otherApp = scanningApp(home: other)
        await finishScan(otherApp)
        let saved = "\(other.path)/Library/Application Support/DevSweep/last-scan.json"
        let copy = "\(home.path)/Library/Application Support/DevSweep/last-scan.json"
        try FileManager.default.createDirectory(
            atPath: (copy as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: saved, toPath: copy)

        let app = scanningApp(home: home)
        #expect(!app.scan.tally.showsPrevious)
        #expect(app.overview.statusLine == "Not scanned yet.")
    }

    @Test
    func `while measuring, an item counts toward the totals`() {
        var row = ScanModel.Row(item: .derivedData)
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
