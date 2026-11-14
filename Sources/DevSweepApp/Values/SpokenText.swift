import DevSweepKit

/// What VoiceOver says for the overview: a label that names a thing, and a
/// value that says its size and its share of the total, or what is
/// happening to it. Written from the tally alone, so each is checked
/// without a model. The ring, the blocks and the rows all say an item
/// through `item(_:in:)`.
struct SpokenText: Equatable {
    let label: String
    let value: String
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

    /// The item, and whether it is marked for cleaning when it can be.
    static func row(_ row: ScanRow, marked: Bool, in tally: Tally) -> SpokenText {
        let item = self.item(row, in: tally)
        guard row.isLive else {
            return item
        }
        return SpokenText(label: item.label, value: "\(item.value), \(marked ? "marked" : "not marked")")
    }

    /// A line of the inspector's lists: "Atlas", "26 MB, built 2026-10-19,
    /// marked". `marked` is nil for a line that can't be ticked.
    static func line(_ name: String, kilobytes: Int64, status: String, marked: Bool?) -> SpokenText {
        let parts = [SizeText.of(kilobytes: kilobytes), status, marked.map { $0 ? "marked" : "not marked" } ?? ""]
        return SpokenText(label: name, value: parts.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    /// The chart as a whole: "307.2 GB reclaimable in 3 items. The largest
    /// is Xcode DerivedData, 67%.", or how far the scan has got.
    static func summary(_ tally: Tally, isScanning: Bool) -> String {
        let total = SizeText.of(kilobytes: tally.reclaimableKilobytes)
        if isScanning {
            let found = tally.showsPrevious ? "\(total), updating" : "\(total) found so far"
            return "\(found), \(tally.measuredCount) of \(tally.rows.count) items measured."
        }
        let live = tally.live
        guard let largest = live.first else {
            return "Nothing to clean."
        }
        let items = live.count == 1 ? "1 item" : "\(live.count) items"
        let share = self.share(largest.shownKilobytes, in: tally).map { ", \($0)" } ?? ""
        return "\(total) reclaimable in \(items). The largest is \(largest.item.name)\(share)."
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
