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
        let app = await scannedApp(home: home)
        #expect(app.scan.tally.live.count == 4)
        #expect(app.marks.marked == [.derivedData, .swiftpmCache, .toolCaches])
    }

    @Test
    func `marks changed during a scan are kept when it ends`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let app = scanningApp(home: home)
        app.scan.scan()
        app.marks.setMarked(.npmCache, true)
        await waitUntil { !app.scan.isScanning && !app.scan.isLoadingExtras }
        #expect(app.marks.marked == [.npmCache])
    }

    @Test
    func `Mark All ticks everything with something to clean, and Mark None nothing`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let app = await scannedApp(home: home)
        app.marks.markAll()
        #expect(app.marks.marked == Set(app.scan.tally.live.map(\.item)))
        #expect(app.marks.markedKilobytes == app.scan.tally.reclaimableKilobytes)
        app.marks.markNone()
        #expect(app.marks.marked.isEmpty)
        #expect(app.marks.markedRows.isEmpty)
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
}
