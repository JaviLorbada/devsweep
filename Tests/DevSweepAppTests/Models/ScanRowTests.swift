import DevSweepKit
import Testing
@testable import DevSweepApp

@Suite("Scan row")
struct ScanRowTests {
    let found = ItemResult(
        item: .cargoBuilds,
        paths: ["/w/ferris/target"],
        kilobytes: 1024,
        location: "",
        folderKilobytes: ["/w/ferris/target": 1024],
        kept: [KeptFolder(path: "/w/ferris/target", repository: "/w/ferris/target/zlib", kilobytes: 1024)])

    @Test
    func `a row counts the folders this scan kept, not the last scan's`() {
        #expect(ScanRow(item: .cargoBuilds, state: .measured, result: self.found).keptCount == 1)
        #expect(ScanRow(item: .cargoBuilds, state: .waiting, previous: self.found).keptCount == 0)
        #expect(ScanRow(item: .gradleBuilds, state: .measured, result: result(.gradleBuilds, kilobytes: 4))
            .keptCount == 0)
    }

    @Test
    func `a clean takes a kept folder when the row goes whole, or when it is one of the parts`() {
        let row = ScanRow(item: .cargoBuilds, state: .measured, result: self.found)
        #expect(row.cleanTakesKeptFolder([]))
        #expect(row.cleanTakesKeptFolder([.folder("/w/ferris/target")]))
        #expect(!row.cleanTakesKeptFolder([.folder("/w/other/target")]))
        #expect(!ScanRow(item: .cargoBuilds, state: .measured, result: result(.cargoBuilds, kilobytes: 4))
            .cleanTakesKeptFolder([]))
    }

    @Test
    func `a row holding a kept folder counts it, but never starts ticked`() {
        let row = ScanRow(item: .swiftpmBuilds, state: .measured, result: self.found)
        #expect(row.isLive)
        #expect(row.kilobytes == 1024)
        #expect(!row.canStartTicked)
        #expect(ScanRow(item: .swiftpmBuilds, state: .measured, result: result(.swiftpmBuilds, kilobytes: 4))
            .canStartTicked)
        #expect(
            !ScanRow(item: .nodeModules, state: .measured, result: result(.nodeModules, kilobytes: 4))
                .canStartTicked,
            "node_modules never does")
    }
}
