import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

/// A home with four items of different sizes: npm's cache the smallest.
func writeFourItems(in home: TemporaryHome) {
    write(256, to: "\(home.path)/Library/Developer/Xcode/DerivedData/Atlas-abc")
    write(192, to: "\(home.path)/Library/Caches/org.swift.swiftpm")
    write(128, to: "\(home.path)/Library/Caches/CocoaPods")
    write(16, to: "\(home.path)/.npm/_cacache")
}

@MainActor
@Suite("Marks")
struct MarksModelTests {
    @Test
    func `the three biggest start ticked once a scan is done`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let model = await scannedModel(home: home)
        #expect(model.scan.tally.live.count == 4)
        #expect(model.marks.marked == [.derivedData, .swiftpmCache, .toolCaches])
    }

    @Test
    func `marks changed during a scan are kept when it ends`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let model = scanningModel(home: home)
        model.scan.scan()
        model.marks.setMarked(.npmCache, true)
        await waitUntil { !model.scan.isScanning && !model.scan.isLoadingExtras }
        #expect(model.marks.marked == [.npmCache])
    }

    @Test
    func `Mark All ticks everything with something to clean, and Mark None nothing`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let model = await scannedModel(home: home)
        model.marks.markAll()
        #expect(model.marks.marked == Set(model.scan.tally.live.map(\.item)))
        #expect(model.marks.markedKilobytes == model.scan.tally.reclaimableKilobytes)
        model.marks.markNone()
        #expect(model.marks.marked.isEmpty)
        #expect(model.marks.markedRows.isEmpty)
    }

    @Test
    func `a new scan starts with nothing ticked`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let model = await scannedModel(home: home)
        model.marks.markAll()
        model.scan.scan()
        #expect(model.marks.marked.isEmpty)
        model.scan.stopScan()
    }
}
