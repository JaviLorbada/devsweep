import DevSweepKit
import Testing
@testable import DevSweepApp

@Suite("Pending clean")
struct PendingCleanTests {
    let rows = measuredRows([result(.derivedData, kilobytes: 64), result(.npmCache, kilobytes: 16)])
    let project = ItemPart.folder("/Users/someone/Library/Developer/Xcode/DerivedData/Atlas-abc")

    @Test
    func `a question about whole items is as big as their rows`() {
        let pending = PendingClean(items: [.derivedData, .npmCache], stage: .confirm, rows: self.rows)
        #expect(pending.kilobytes == 80)
        #expect(pending.parts.isEmpty)
        #expect(PendingClean(items: [.homebrew], stage: .confirm, rows: self.rows).kilobytes == 0)
    }

    @Test
    func `the others are the items that can go with Xcode open`() {
        let pending = PendingClean(items: [.derivedData, .npmCache], stage: .quitApps([.xcode]), rows: self.rows)
        #expect(pending.others?.items == [.npmCache])
        #expect(pending.others?.parts == [])
        #expect(pending.hasOthers)

        let xcodeOnly = PendingClean(items: [.derivedData], stage: .quitApps([.xcode]), rows: self.rows)
        #expect(xcodeOnly.others == nil)
        #expect(!xcodeOnly.hasOthers)
    }

    @Test
    func `the others of some parts are those that can go with Xcode open`() {
        let pending = PendingClean(
            items: [.derivedData],
            stage: .quitApps([.xcode]),
            parts: [.compilationCache, self.project])
        #expect(pending.others?.items == [.derivedData])
        #expect(pending.others?.parts == [self.project])

        let caches = PendingClean(items: [.derivedData], stage: .quitApps([.xcode]), parts: [.compilationCache])
        #expect(caches.others == nil)
        #expect(!caches.hasOthers)
    }
}
