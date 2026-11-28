import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Marks")
struct MarksModelTests {
    /// Four measured items, DerivedData the biggest and npm's cache the smallest.
    let scan = FakeScanResults([
        result(.derivedData, kilobytes: 256),
        result(.swiftpmCache, kilobytes: 192),
        result(.toolCaches, kilobytes: 128),
        result(.npmCache, kilobytes: 16),
    ])

    @Test
    func `the three biggest start ticked`() {
        let marks = MarksModel(scan: self.scan)
        #expect(marks.marked.isEmpty)
        marks.applyDefaults()
        #expect(marks.marked == [.derivedData, .swiftpmCache, .toolCaches])
    }

    @Test
    func `an item holding a kept folder never starts ticked, however big`() {
        let ledger = "/Users/someone/Developer/Ledger/.build"
        let scan = FakeScanResults([
            ItemResult(
                item: .swiftpmBuilds,
                paths: [ledger],
                kilobytes: 4096,
                location: "",
                kept: [KeptFolder(path: ledger, repository: ledger, kilobytes: 4096)]),
            result(.derivedData, kilobytes: 256),
        ])
        let marks = MarksModel(scan: scan)
        marks.applyDefaults()
        #expect(marks.marked == [.derivedData])
    }

    @Test
    func `other languages' build folders never start ticked, however big`() {
        let scan = FakeScanResults([
            result(.nodeModules, kilobytes: 4096),
            result(.cargoBuilds, kilobytes: 2048),
            result(.cocoapodsPods, kilobytes: 1024),
            result(.derivedData, kilobytes: 256),
            result(.swiftpmCache, kilobytes: 192),
            result(.toolCaches, kilobytes: 128),
            result(.npmCache, kilobytes: 16),
        ])
        let marks = MarksModel(scan: scan)
        marks.applyDefaults()
        #expect(marks.marked == [.derivedData, .swiftpmCache, .toolCaches])

        marks.markAll()
        #expect(marks.marked.isSuperset(of: [.nodeModules, .cargoBuilds, .cocoapodsPods]))
    }

    @Test
    func `marks changed before the defaults apply are kept, until a new scan`() {
        let marks = MarksModel(scan: self.scan)
        marks.setMarked(.npmCache, true)
        marks.applyDefaults()
        #expect(marks.marked == [.npmCache])

        marks.reset()
        #expect(marks.marked.isEmpty)
        marks.applyDefaults()
        #expect(marks.marked == [.derivedData, .swiftpmCache, .toolCaches])
    }

    @Test
    func `Mark All ticks everything with something to clean, and Mark None nothing`() {
        let marks = MarksModel(scan: self.scan)
        marks.markAll()
        #expect(marks.marked == [.derivedData, .swiftpmCache, .toolCaches, .npmCache])
        #expect(marks.markedKilobytes == 256 + 192 + 128 + 16)
        #expect(marks.markedRows.map(\.item) == [.derivedData, .swiftpmCache, .toolCaches, .npmCache])
        marks.markNone()
        #expect(marks.marked.isEmpty)
        #expect(marks.markedRows.isEmpty)
    }

    @Test
    func `what was cleaned can't stay ticked, item or part`() {
        let marks = MarksModel(scan: self.scan)
        marks.markAll()
        marks.cleaned(.derivedData)
        #expect(!marks.marked.contains(.derivedData))

        marks.setMarked(.compilationCache, of: .derivedData, true)
        marks.setMarked(.folder("/dd/Atlas-abc"), of: .derivedData, true)
        marks.cleaned([.compilationCache], of: .derivedData)
        #expect(marks.markedParts(of: .derivedData) == [.folder("/dd/Atlas-abc")])
        marks.setMarked(.folder("/dd/Atlas-abc"), of: .derivedData, false)
        #expect(marks.markedParts(of: .derivedData).isEmpty)
    }
}
