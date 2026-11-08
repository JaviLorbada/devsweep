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
        let model = makeModel(home: home)
        model.showResults(sampleResults.filter { model.scan.scanOrder.contains($0.item) })
        model.rewindScan(toMeasured: 3)
        let order = model.scan.scanOrder
        let size = { (item: Item) in sampleResults.first { $0.item == item }?.kilobytes ?? 0 }

        let measured = order.prefix(3).sorted { size($0) > size($1) }
        let waiting = order.dropFirst(4).sorted { size($0) > size($1) }
        #expect(model.scan.tally.ordered.map(\.item) == measured + [order[3]] + waiting)
        #expect(model.scan.tally.measuringItems == [order[3]])
        #expect(model.scan.tally.measuredCount == 3)
        #expect(model.scan.tally.showsPrevious)
    }

    @Test
    func `the ring weighs each row by what is known of its size`() throws {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        model.showResults(sampleResults.filter { model.scan.scanOrder.contains($0.item) })
        model.rewindScan(toMeasured: 3)
        let order = model.scan.scanOrder
        let row = { (index: Int) in try #require(model.scan.rows[order[index]]) }

        // Measured: its size. Being measured: the count so far. Waiting: the last scan's size.
        #expect(try model.scan.tally.chartWeight(row(0)) == Double(row(0).kilobytes))
        #expect(try model.scan.tally.chartWeight(row(3)) == Double(row(3).progressBytes / 1024))
        #expect(try model.scan.tally.chartWeight(row(5)) == Double(row(5).previous?.kilobytes ?? -1))
    }

    @Test
    func `a stopped scan says how far it got`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let model = scanningModel(home: home)
        model.scan.scan()
        model.scan.stopScan()
        await waitUntil { !model.scan.isScanTaskRunning }
        #expect(!model.scan.isScanning)
        let notMeasured = model.scan.scanOrder.filter { model.scan.rows[$0]?.state == .notMeasured }
        if notMeasured.isEmpty {
            #expect(model.statusLine.hasPrefix("Scanned just now"))
        } else {
            #expect(model.statusLine
                .hasPrefix("Stopped after \(model.scan.tally.measuredCount) of \(model.scan.scanOrder.count) items."))
        }
    }
}
