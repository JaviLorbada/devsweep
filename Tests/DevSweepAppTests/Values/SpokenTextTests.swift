import Testing
@testable import DevSweepApp

// A cleaned row's outcome has no public initializer: only the kit makes one.
@testable import DevSweepKit

@Suite("Spoken text")
struct SpokenTextTests {
    /// 204.8 GB, 102.4 GB and 1 MB: two thirds, one third and a sliver.
    let measured = tally([
        row(.derivedData, .measured, kilobytes: 200_000_000),
        row(.npmCache, .measured, kilobytes: 100_000_000),
        row(.homebrew, .measured, kilobytes: 1000),
    ])

    @Test
    func `an item says its name, then its size and its share of the total`() {
        let rows = self.measured.rows
        #expect(SpokenText.item(rows[0], in: self.measured)
            == SpokenText(label: "Xcode DerivedData", value: "204.8 GB, 67%"))
        #expect(SpokenText.item(rows[1], in: self.measured) == SpokenText(label: "npm cache", value: "102.4 GB, 33%"))
        #expect(SpokenText.item(rows[2], in: self.measured).value == "1 MB, under 1%")
    }

    @Test
    func `an item not measured yet says what is happening to it`() {
        let rows = tally([
            row(.derivedData, .waiting, kilobytes: 0, previous: 3000),
            row(.npmCache, .waiting, kilobytes: 0),
            row(.homebrew, .measuring, kilobytes: 1000),
            row(.toolCaches, .measuring, kilobytes: 0),
            row(.gradleBuilds, .notMeasured, kilobytes: 0),
        ])
        #expect(rows.rows.map { SpokenText.item($0, in: rows).value } == [
            "3 MB, 75%, from the last scan",
            "waiting",
            "measuring, 1 MB so far",
            "measuring",
            "not measured",
        ])
    }

    @Test
    func `a measured item with nothing to clean, or no size, says so`() {
        var unknown = row(.simulators, .measured, kilobytes: 0)
        unknown.result = ItemResult(item: .simulators, paths: ["/a"], kilobytes: 0, location: "", sizeKnown: false)
        let rows = tally([row(.npmCache, .measured, kilobytes: 0), unknown])
        #expect(rows.rows.map { SpokenText.item($0, in: rows).value } == ["nothing to clean", "size unknown"])
    }

    @Test
    func `an item being cleaned says what is left, and once cleaned where it went`() {
        var cleaning = row(.derivedData, .cleaning, kilobytes: 3000)
        cleaning.removedBytes = 1000 * 1024
        var trashed = row(.npmCache, .cleaned, kilobytes: 2000)
        trashed.outcome = CleanOutcome(item: .npmCache, mode: .trash, removed: [.init(original: "/a", trashed: "/t")])
        var deleted = row(.homebrew, .cleaned, kilobytes: 1000)
        deleted.outcome = CleanOutcome(item: .homebrew, mode: .delete, removed: [.init(original: "/b", trashed: nil)])
        let rows = tally([cleaning, trashed, deleted])
        #expect(rows.rows.map { SpokenText.item($0, in: rows).value } == [
            "cleaning, 2 MB left",
            "2 MB, in the Trash",
            "1 MB, deleted",
        ])
    }

    @Test
    func `a family says its size and share, or that none of it is measured yet`() {
        #expect(SpokenText.family(.xcode, in: self.measured) == SpokenText(label: "Xcode", value: "204.8 GB, 67%"))
        #expect(SpokenText.family(.otherTools, in: self.measured)
            == SpokenText(label: "Other tools", value: "not measured"))
    }

    @Test
    func `a row says the item as the row shows it, and whether it is marked when it can be`() {
        let rows = self.measured.rows
        #expect(SpokenText.row(rows[0], marked: true, in: self.measured)
            == SpokenText(label: "Xcode DerivedData, Xcode", value: "204.8 GB, 67%, marked"))
        #expect(SpokenText.row(rows[1], marked: false, in: self.measured).value == "102.4 GB, 33%, not marked")
        let waiting = tally([row(.npmCache, .waiting, kilobytes: 0)])
        #expect(SpokenText.row(waiting.rows[0], marked: false, in: waiting).value == "waiting")
        // With how many folders it found, as the row's name shows it.
        var caches = row(.toolCaches, .measured, kilobytes: 0)
        caches.result = ItemResult(item: .toolCaches, paths: ["/a", "/b", "/c"], kilobytes: 9000, location: "")
        #expect(SpokenText.row(caches, marked: false, in: tally([caches])).label == "Tool caches (3), Other tools")
    }

    @Test
    func `a line of the inspector's lists says its size, its status, whether it is marked and its folder`() {
        #expect(SpokenText.line("Atlas", detail: nil, kilobytes: 25000, status: "built 2026-10-19", marked: true)
            == SpokenText(label: "Atlas", value: "26 MB, built 2026-10-19, marked"))
        #expect(SpokenText.line("Shared module cache", detail: nil, kilobytes: 9000, status: "", marked: false).value
            == "9 MB, not marked")
        #expect(SpokenText.line("2 more projects", detail: nil, kilobytes: 3000, status: "", marked: nil).value
            == "3 MB")
        #expect(SpokenText.line("kite-1", detail: "~/w/kite-1/.build", kilobytes: 3000, status: "", marked: false)
            .value == "3 MB, not marked, ~/w/kite-1/.build")
    }

    @Test
    func `the total is its size, and whether it is all there is, found so far or updating`() {
        #expect(SpokenText.total(self.measured, isScanning: false)
            == SpokenText(label: "307.2 GB", value: "reclaimable"))
        let scanning = tally([row(.npmCache, .measured, kilobytes: 1000), row(.homebrew, .measuring, kilobytes: 0)])
        #expect(SpokenText.total(scanning, isScanning: true) == SpokenText(label: "1 MB", value: "found so far"))
        let updating = tally([
            row(.npmCache, .measured, kilobytes: 1000),
            row(.homebrew, .waiting, kilobytes: 0, previous: 2000),
        ])
        #expect(SpokenText.total(updating, isScanning: true) == SpokenText(label: "3 MB", value: "updating"))
    }

    @Test
    func `as one sentence, a label and a value are joined, and an empty label is left out`() {
        #expect(SpokenText(label: "204.8 GB", value: "reclaimable").sentence == "204.8 GB, reclaimable")
        #expect(SpokenText(label: "", value: "waiting").sentence == "waiting")
    }

    @Test
    func `the inspector's headline is the size as shown and the item's state, with no size until there is one`() {
        var cleaning = row(.derivedData, .cleaning, kilobytes: 3000)
        cleaning.removedBytes = 1000 * 1024
        var trashed = row(.npmCache, .cleaned, kilobytes: 2000)
        trashed.outcome = CleanOutcome(item: .npmCache, mode: .trash, removed: [.init(original: "/a", trashed: "/t")])
        var unknown = row(.simulators, .measured, kilobytes: 0)
        unknown.result = ItemResult(item: .simulators, paths: ["/a"], kilobytes: 0, location: "", sizeKnown: false)
        let rows = [
            row(.derivedData, .measured, kilobytes: 200_000_000),
            row(.npmCache, .measured, kilobytes: 0),
            unknown,
            row(.homebrew, .waiting, kilobytes: 0, previous: 3000),
            row(.homebrew, .waiting, kilobytes: 0),
            row(.homebrew, .measuring, kilobytes: 1000),
            row(.homebrew, .measuring, kilobytes: 0),
            row(.homebrew, .notMeasured, kilobytes: 0),
            row(.derivedData, .cleaning, kilobytes: 3000),
            cleaning,
            trashed,
        ]
        #expect(rows.map(SpokenText.headline) == [
            SpokenText(label: "204.8 GB", value: "reclaimable"),
            SpokenText(label: "0 KB", value: "nothing to clean"),
            SpokenText(label: "", value: "size unknown"),
            SpokenText(label: "3 MB", value: "last scan, waiting"),
            SpokenText(label: "", value: "waiting"),
            SpokenText(label: "1 MB", value: "measuring"),
            SpokenText(label: "", value: "measuring"),
            SpokenText(label: "", value: "not measured"),
            SpokenText(label: "3 MB", value: "cleaning"),
            SpokenText(label: "2 MB", value: "left to delete"),
            SpokenText(label: "2 MB", value: "in the Trash"),
        ])
    }

    @Test
    func `the chart's summary says the total, in how many items, and the largest`() {
        #expect(SpokenText.summary(self.measured, isScanning: false)
            == "307.2 GB reclaimable in 3 items. The largest is Xcode DerivedData, 67%.")
        let one = tally([row(.npmCache, .measured, kilobytes: 1000), row(.homebrew, .measured, kilobytes: 0)])
        #expect(SpokenText
            .summary(one, isScanning: false) == "1 MB reclaimable in 1 item. The largest is npm cache, 100%.")
        #expect(SpokenText.summary(tally([row(.npmCache, .measured, kilobytes: 0)]), isScanning: false)
            == "Nothing to clean.")
    }

    @Test
    func `while scanning the summary counts what is found and measured, and says when it is updating`() {
        let scanning = tally([row(.npmCache, .measured, kilobytes: 1000), row(.homebrew, .measuring, kilobytes: 0)])
        #expect(SpokenText.summary(scanning, isScanning: true) == "1 MB, found so far, 1 of 2 items measured.")
        let updating = tally([row(.npmCache, .measured, kilobytes: 1000), row(
            .homebrew,
            .waiting,
            kilobytes: 0,
            previous: 2000)])
        #expect(SpokenText.summary(updating, isScanning: true) == "3 MB, updating, 1 of 2 items measured.")
    }
}
