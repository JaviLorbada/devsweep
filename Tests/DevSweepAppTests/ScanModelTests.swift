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
        model.showResults(sampleResults.filter { model.scanOrder.contains($0.item) })
        model.rewindScan(toMeasured: 3)
        let order = model.scanOrder
        let size = { (item: Item) in sampleResults.first { $0.item == item }?.kilobytes ?? 0 }

        let measured = order.prefix(3).sorted { size($0) > size($1) }
        let waiting = order.dropFirst(4).sorted { size($0) > size($1) }
        #expect(model.orderedRows.map(\.item) == measured + [order[3]] + waiting)
        #expect(model.measuringItems == [order[3]])
        #expect(model.measuredCount == 3)
        #expect(model.showsPrevious)
    }

    @Test
    func `the ring weighs each row by what is known of its size`() throws {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        model.showResults(sampleResults.filter { model.scanOrder.contains($0.item) })
        model.rewindScan(toMeasured: 3)
        let order = model.scanOrder
        let row = { (index: Int) in try #require(model.rows[order[index]]) }

        // Measured: its size. Being measured: the count so far. Waiting: the last scan's size.
        #expect(try model.chartWeight(row(0)) == Double(row(0).kilobytes))
        #expect(try model.chartWeight(row(3)) == Double(row(3).progressBytes / 1024))
        #expect(try model.chartWeight(row(5)) == Double(row(5).previous?.kilobytes ?? -1))
    }

    @Test
    func `a stopped scan says how far it got`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let model = scanningModel(home: home)
        model.scan()
        model.stopScan()
        await waitUntil { !model.isScanTaskRunning }
        #expect(!model.isScanning)
        let notMeasured = model.scanOrder.filter { model.rows[$0]?.state == .notMeasured }
        if notMeasured.isEmpty {
            #expect(model.statusLine.hasPrefix("Scanned just now"))
        } else {
            #expect(model.statusLine
                .hasPrefix("Stopped after \(model.measuredCount) of \(model.scanOrder.count) items."))
        }
    }
}
