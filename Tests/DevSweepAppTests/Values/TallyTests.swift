import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

/// A row for `item` in `state`: measured at `kilobytes`, or with that much
/// from the last scan when it hasn't been measured.
func row(_ item: Item, _ state: ScanModel.RowState, kilobytes: Int64, previous: Int64? = nil) -> ScanModel.Row {
    var row = ScanModel.Row(item: item)
    row.state = state
    let result = { (kilobytes: Int64) in
        ItemResult(item: item, paths: kilobytes > 0 ? ["/\(item.rawValue)"] : [], kilobytes: kilobytes, location: "")
    }
    switch state {
    case .measured, .cleaning, .cleaned: row.result = result(kilobytes)
    case .measuring: row.progressBytes = kilobytes * 1024
    case .waiting, .notMeasured: break
    }
    row.previous = previous.map(result)
    return row
}

func tally(_ rows: [ScanModel.Row]) -> Tally {
    Tally(order: rows.map(\.item), rows: Dictionary(uniqueKeysWithValues: rows.map { ($0.item, $0) }))
}

@Suite("Tally")
struct TallyTests {
    @Test
    func `measured rows come first by size, then the one measuring, then the rest by the last scan`() {
        let rows = tally([
            row(.npmCache, .measured, kilobytes: 10),
            row(.derivedData, .waiting, kilobytes: 0, previous: 50),
            row(.homebrew, .measuring, kilobytes: 5),
            row(.swiftpmCache, .measured, kilobytes: 90),
            row(.toolCaches, .notMeasured, kilobytes: 0, previous: 70),
            row(.gradleBuilds, .measured, kilobytes: 0),
        ])
        #expect(rows.ordered.map(\.item)
            == [.swiftpmCache, .npmCache, .gradleBuilds, .homebrew, .toolCaches, .derivedData])
        #expect(rows.live.map(\.item) == [.swiftpmCache, .npmCache], "nothing to clean in an empty one")
        #expect(rows.measuredCount == 3)
        #expect(rows.notMeasuredCount == 1)
        #expect(rows.measuringItems == [.homebrew])
        #expect(rows.progress == 0.5)
    }

    @Test
    func `the total counts this scan's sizes, the running counts and the last scan's for what is waiting`() {
        let rows = tally([
            row(.npmCache, .measured, kilobytes: 10),
            row(.homebrew, .measuring, kilobytes: 5),
            row(.derivedData, .waiting, kilobytes: 0, previous: 50),
            row(.toolCaches, .notMeasured, kilobytes: 0, previous: 70),
        ])
        #expect(rows.reclaimableKilobytes == 65)
        #expect(rows.kilobytes(of: .xcode) == 50)
        #expect(rows.showsPrevious)
        #expect(rows.familyShowsPrevious(.xcode))
        #expect(!rows.familyShowsPrevious(.npm))
        #expect(rows.measuredKilobytes(of: .otherTools) == nil, "nothing known yet")
        #expect(rows.markedKilobytes([.npmCache, .homebrew]) == 10, "only what can be cleaned")
    }

    @Test
    func `a waiting row with no last scan weighs the average so far, and an unmeasured one nothing`() {
        let rows = tally([
            row(.npmCache, .measured, kilobytes: 10),
            row(.swiftpmCache, .measured, kilobytes: 30),
            row(.derivedData, .waiting, kilobytes: 0),
            row(.homebrew, .waiting, kilobytes: 0, previous: 0),
            row(.toolCaches, .notMeasured, kilobytes: 0, previous: 70),
        ])
        #expect(rows.chartWeight(rows.rows[2]) == 20)
        #expect(rows.chartWeight(rows.rows[3]) == 1, "never nothing, so the segment shows")
        #expect(rows.chartWeight(rows.rows[4]) == 0)
        #expect(tally([row(.derivedData, .waiting, kilobytes: 0)]).chartWeight(row(
            .derivedData,
            .waiting,
            kilobytes: 0))
            == 1)
    }

    @Test
    func `the sidebar's sizes are the listings' sums, worktrees only those with nothing to lose`() {
        #expect(sampleExtras.xcodesKilobytes == 12_582_912 + 11_534_336)
        #expect(sampleExtras.runtimesKilobytes == 7_689_179 + 8_295_197 + 4_089_446)
        #expect(sampleExtras.removableWorktreesKilobytes == 2 * 623_000)
        #expect(sampleAndroid.studiosKilobytes == 3_500_000)
        #expect(sampleAndroid.sdkKilobytes == 9_000_000 + 120_000 + 150_000 + 900_000 + 6_000_000)
        #expect(sampleAndroid.gradleCachesKilobytes == 4_000_000)
    }
}
