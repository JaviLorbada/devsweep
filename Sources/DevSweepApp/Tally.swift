import DevSweepKit

/// What the window lists, sums and draws, worked out from the rows alone:
/// their order, the totals, each family's share and the ring's weights.
/// A value, so it is checked without a model.
struct Tally {
    typealias Row = AppModel.Row

    /// The rows in the order the scan measures them.
    let rows: [Row]
    private let byItem: [Item: Row]

    init(order: [Item], rows: [Item: Row]) {
        self.rows = order.compactMap { rows[$0] }
        self.byItem = rows
    }

    /// Measured items largest first, then the ones being measured, then the
    /// rest; those two by what the last scan found, so rows keep their places.
    var ordered: [Row] {
        let byPrevious = { (a: Row, b: Row) in (a.previous?.kilobytes ?? 0) > (b.previous?.kilobytes ?? 0) }
        let measured = self.rows.filter(\.wasMeasured).sorted { $0.kilobytes > $1.kilobytes }
        return measured + self.rows.filter { $0.state == .measuring }.sorted(by: byPrevious)
            + self.rows.filter { $0.state == .waiting || $0.state == .notMeasured }.sorted(by: byPrevious)
    }

    /// Measured, with something to clean, largest first.
    var live: [Row] {
        self.ordered.filter(\.isLive)
    }

    /// The live rows among `marked`, largest first.
    func marked(_ marked: Set<Item>) -> [Row] {
        self.live.filter { marked.contains($0.item) }
    }

    func markedKilobytes(_ marked: Set<Item>) -> Int64 {
        self.marked(marked).reduce(0) { $0 + $1.kilobytes }
    }

    /// Rows whose size counts toward the totals on screen: measured with
    /// something to reclaim, counting up, or still showing the last scan.
    private var counted: [Row] {
        self.ordered.filter { $0.isLive || $0.isCounting || $0.showsPrevious }
    }

    /// The total on screen: this scan's sizes where it has them, the running
    /// counts, and the last scan's sizes for what it hasn't reached yet.
    var reclaimableKilobytes: Int64 {
        self.counted.reduce(0) { $0 + $1.shownKilobytes }
    }

    func kilobytes(of family: Family) -> Int64 {
        self.counted.filter { $0.item.family == family }.reduce(0) { $0 + $1.shownKilobytes }
    }

    /// What each family takes of the legend's bar: the sum of its items'
    /// shares, with small items drawn larger (`ChartScale`), as the ring's
    /// inner circle draws it once the scan is done.
    var familyChartShares: [Family: Double] {
        let rows = self.counted
        let shares = ChartScale.shares(rows.map { Double($0.shownKilobytes) })
        return zip(rows, shares).reduce(into: [:]) { $0[$1.0.item.family, default: 0] += $1.1 }
    }

    /// The family's size once anything is known about it, nil before.
    func measuredKilobytes(of family: Family) -> Int64? {
        let known = family.items.contains { item in
            guard let row = self.byItem[item] else { return false }
            return row.wasMeasured || row.isCounting || row.showsPrevious
        }
        return known ? self.kilobytes(of: family) : nil
    }

    /// Whether everything shown for the family comes from the last scan.
    func familyShowsPrevious(_ family: Family) -> Bool {
        let rows = family.items.compactMap { self.byItem[$0] }
        return rows.contains(where: \.showsPrevious) && !rows.contains { $0.wasMeasured || $0.isCounting }
    }

    /// Whether the totals still lean on the last scan.
    var showsPrevious: Bool {
        self.rows.contains(where: \.showsPrevious)
    }

    var measuredCount: Int {
        self.rows.filter(\.wasMeasured).count
    }

    /// Items the scan stopped before reaching.
    var notMeasuredCount: Int {
        self.rows.filter { $0.state == .notMeasured }.count
    }

    var measuringItems: [Item] {
        self.rows.filter { $0.state == .measuring }.map(\.item)
    }

    /// How far the scan has got, from 0 to 1.
    var progress: Double {
        self.rows.isEmpty ? 0 : Double(self.measuredCount) / Double(self.rows.count)
    }

    /// The weight a ring segment gets: its size once measured, otherwise what
    /// it took last time or the average so far, so the ring is whole from the start.
    func chartWeight(_ row: Row) -> Double {
        switch row.state {
        case .measured, .cleaning, .cleaned:
            return Double(max(row.kilobytes, 0))
        case .notMeasured:
            return 0
        case .measuring where row.progressBytes > 0:
            return Double(row.progressBytes / 1024)
        case .waiting, .measuring:
            if let previous = row.previous { return Double(max(previous.kilobytes, 1)) }
            let measured = self.rows.filter(\.wasMeasured)
            let total = measured.reduce(0) { $0 + Double($1.kilobytes) }
            return measured.isEmpty || total == 0 ? 1 : total / Double(measured.count)
        }
    }
}

/// The sizes the sidebar shows for the listings.
extension Extras {
    var xcodesKilobytes: Int64 {
        self.xcodes.reduce(0) { $0 + $1.kilobytes }
    }

    var runtimesKilobytes: Int64 {
        self.runtimes.reduce(0) { $0 + $1.kilobytes }
    }

    /// What removing every worktree with nothing to lose would free. The
    /// sidebar shows this, not the total, since the others stay.
    var removableWorktreesKilobytes: Int64 {
        self.worktrees.filter { $0.keptBecause == nil }.reduce(0) { $0 + $1.kilobytes }
    }
}

extension AndroidReport {
    var studiosKilobytes: Int64 {
        Self.total(self.studios)
    }

    var sdkKilobytes: Int64 {
        Self.total(self.sdkEntries + self.emulators)
    }

    var gradleCachesKilobytes: Int64 {
        Self.total(self.gradleCaches)
    }

    private static func total(_ entries: [AndroidEntry]) -> Int64 {
        entries.reduce(0) { $0 + $1.kilobytes }
    }
}
