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
}
