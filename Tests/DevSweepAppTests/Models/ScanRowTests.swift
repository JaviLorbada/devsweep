import DevSweepKit
import Testing
@testable import DevSweepApp

@Suite("Scan row")
struct ScanRowTests {
    @Test
    func `a row counts the folders this scan kept, not the last scan's`() {
        let kept = [KeptFolder(path: "/w/ferris/target", repository: "/w/ferris/target/zlib", kilobytes: 1024)]
        let found = ItemResult(item: .cargoBuilds, paths: [], kilobytes: 0, location: "", kept: kept)
        #expect(ScanRow(item: .cargoBuilds, state: .measured, result: found).keptCount == 1)
        #expect(ScanRow(item: .cargoBuilds, state: .waiting, previous: found).keptCount == 0)
        #expect(ScanRow(item: .gradleBuilds, state: .measured, result: result(.gradleBuilds, kilobytes: 4))
            .keptCount == 0)
    }

    @Test
    func `a row with only kept folders has parts to tick, but nothing a whole clean takes`() {
        let kept = [KeptFolder(path: "/w/ferris/target", repository: "/w/ferris/target/zlib", kilobytes: 1024)]
        let found = ItemResult(item: .cargoBuilds, paths: [], kilobytes: 0, location: "", kept: kept)
        let row = ScanRow(item: .cargoBuilds, state: .measured, result: found)
        #expect(row.hasPartsToClean)
        #expect(!row.isLive)
        #expect(!ScanRow(item: .cargoBuilds, state: .cleaning, result: found).hasPartsToClean)
        var cleaning = ScanRow(item: .cargoBuilds, state: .cleaning, result: found, cleaningKilobytes: 1024)
        cleaning.removedBytes = 256 * 1024
        #expect(cleaning.leftKilobytes == 768, "counting down from the kept folder, not the item's 0 KB")
        #expect(!ScanRow(item: .cargoBuilds, state: .measured, result: result(.cargoBuilds, kilobytes: 0))
            .hasPartsToClean)
    }
}
