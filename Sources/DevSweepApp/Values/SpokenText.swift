import DevSweepKit

/// The overview's words for sizes, to VoiceOver and in its headlines: a
/// label that names a thing, and a value that says its size and its share of
/// the total, or what is happening to it. Written from the rows and the
/// tally alone, so each is checked without a model. The ring, the blocks and
/// the rows all say an item through `item(_:in:)`, and the charts and the
/// summary say the total through `total(_:isScanning:)`.
struct SpokenText: Equatable {
    let label: String
    let value: String

    /// The label and the value as one: "204.8 GB, reclaimable", or
    /// "waiting" with no label. For a group, whose value VoiceOver doesn't read.
    var sentence: String {
        self.label.isEmpty ? self.value : "\(self.label), \(self.value)"
    }
}

extension SpokenText {
    /// "Xcode DerivedData", "204.8 GB, 67%"; or "measuring, 1 MB so far",
    /// "cleaning, 2 MB left", "2 MB, in the Trash".
    static func item(_ row: ScanRow, in tally: Tally) -> SpokenText {
        SpokenText(label: row.item.name, value: self.state(of: row, in: tally))
    }

    /// "Xcode", "204.8 GB, 67%", or "not measured" before the scan reaches it.
    static func family(_ family: Family, in tally: Tally) -> SpokenText {
        let value = tally.measuredKilobytes(of: family).map { self.sized($0, in: tally) } ?? "not measured"
        return SpokenText(label: family.name, value: value)
    }

    /// The item as its row shows it, "Tool caches (3), Other tools", and
    /// whether it is marked for cleaning when it can be.
    static func row(_ row: ScanRow, marked: Bool, in tally: Tally) -> SpokenText {
        let label = "\(row.result?.label ?? row.item.name), \(row.item.family.name)"
        let value = self.item(row, in: tally).value
        guard row.isLive else {
            return SpokenText(label: label, value: value)
        }
        return SpokenText(label: label, value: "\(value), \(marked ? "marked" : "not marked")")
    }

    /// A line of the inspector's lists: "kite-1", "26 MB, built 2026-10-19,
    /// marked, ~/w/kite-1/.build". `marked` is nil for a line that can't be
    /// ticked, and `detail` the folder a build folder's line shows under it.
    static func line(_ name: String, detail: String?, kilobytes: Int64, status: String, marked: Bool?) -> SpokenText {
        let marks = marked.map { $0 ? "marked" : "not marked" }
        let parts = [SizeText.of(kilobytes: kilobytes), status, marks ?? "", detail ?? ""]
        return SpokenText(label: name, value: parts.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    /// The total the charts show, "307.2 GB", and the word under it:
    /// "reclaimable", or while scanning "found so far", or "updating" while
    /// the last scan's sizes still count.
    static func total(_ tally: Tally, isScanning: Bool) -> SpokenText {
        let word = !isScanning ? "reclaimable" : tally.showsPrevious ? "updating" : "found so far"
        return SpokenText(label: SizeText.of(kilobytes: tally.reclaimableKilobytes), value: word)
    }

    /// The inspector's headline: the size as it shows it, empty until there
    /// is one, and the item's state.
    static func headline(_ row: ScanRow) -> SpokenText {
        switch row.state {
        case .waiting where row.showsPrevious:
            SpokenText(label: SizeText.of(kilobytes: row.shownKilobytes), value: "last scan, waiting")
        case .waiting: SpokenText(label: "", value: "waiting")
        case .notMeasured: SpokenText(label: "", value: "not measured")
        case .measuring:
            SpokenText(label: row.progressBytes > 0 ? SizeText.of(bytes: row.progressBytes) : "", value: "measuring")
        case .measured:
            SpokenText(
                label: !row.sizeKnown && row.kilobytes == 0 ? "" : SizeText.of(kilobytes: row.kilobytes),
                value: !row.sizeKnown ? "size unknown" : row.isLive ? "reclaimable" : "nothing to clean")
        case .cleaning:
            SpokenText(
                label: SizeText.of(kilobytes: row.leftKilobytes),
                value: row.cleaningProgress == nil ? "cleaning" : "left to delete")
        case .cleaned:
            SpokenText(label: SizeText.of(kilobytes: row.kilobytes), value: row.canPutBack ? "in the Trash" : "deleted")
        }
    }

    /// The chart as a whole: "307.2 GB reclaimable in 3 items. The largest
    /// is Xcode DerivedData, 67%.", or how far the scan has got.
    static func summary(_ tally: Tally, isScanning: Bool) -> String {
        let total = self.total(tally, isScanning: isScanning)
        if isScanning {
            return "\(total.label), \(total.value), \(tally.measuredCount) of \(tally.rows.count) items measured."
        }
        let live = tally.live
        guard let largest = live.first else {
            return "Nothing to clean."
        }
        let items = live.count == 1 ? "1 item" : "\(live.count) items"
        let share = self.share(largest.shownKilobytes, in: tally).map { ", \($0)" } ?? ""
        return "\(total.label) \(total.value) in \(items). The largest is \(largest.item.name)\(share)."
    }

    private static func state(of row: ScanRow, in tally: Tally) -> String {
        switch row.state {
        case .waiting where row.showsPrevious && row.shownKilobytes > 0:
            "\(self.sized(row.shownKilobytes, in: tally)), from the last scan"
        case .waiting: "waiting"
        case .measuring where row.progressBytes > 0: "measuring, \(SizeText.of(bytes: row.progressBytes)) so far"
        case .measuring: "measuring"
        case .notMeasured: "not measured"
        case .cleaning: "cleaning, \(SizeText.of(kilobytes: row.leftKilobytes)) left"
        case .cleaned: "\(SizeText.of(kilobytes: row.kilobytes)), \(row.canPutBack ? "in the Trash" : "deleted")"
        case .measured where !row.sizeKnown && row.kilobytes == 0: "size unknown"
        case .measured where !row.isLive: "nothing to clean"
        case .measured: self.sized(row.kilobytes, in: tally)
        }
    }

    /// "204.8 GB, 67%", or the size alone while nothing counts.
    private static func sized(_ kilobytes: Int64, in tally: Tally) -> String {
        let size = SizeText.of(kilobytes: kilobytes)
        return self.share(kilobytes, in: tally).map { "\(size), \($0)" } ?? size
    }

    /// "67%" as the legend writes it, and "under 1%" for a sliver the legend
    /// would round to nothing.
    private static func share(_ kilobytes: Int64, in tally: Tally) -> String? {
        tally.percent(of: kilobytes).map { $0 == 0 && kilobytes > 0 ? "under 1%" : "\($0)%" }
    }
}
