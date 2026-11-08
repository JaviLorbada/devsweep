import DevSweepKit
import Observation

/// What is ticked to clean: whole items in the list, and parts of an item
/// in its inspector. The three biggest start ticked once a scan is done.
@MainActor
@Observable
final class MarksModel: Marking {
    private(set) var marked: Set<Item> = []
    /// Parts of items ticked in the inspector, cleaned on their own.
    private(set) var partMarks: [Item: Set<ItemPart>] = [:]
    /// Whether the marks were changed since the scan started, so the
    /// defaults leave them alone.
    private var touched = false
    private let scan: any ScanResults

    init(scan: any ScanResults) {
        self.scan = scan
    }

    /// The ticked rows that can be cleaned, largest first.
    var markedRows: [ScanRow] {
        self.scan.tally.marked(self.marked)
    }

    var markedKilobytes: Int64 {
        self.scan.tally.markedKilobytes(self.marked)
    }

    func setMarked(_ item: Item, _ isMarked: Bool) {
        self.touched = true
        if isMarked { self.marked.insert(item) } else { self.marked.remove(item) }
    }

    /// Ticks everything with something to clean.
    func markAll() {
        self.touched = true
        self.marked = Set(self.scan.tally.live.map(\.item))
    }

    func markNone() {
        self.touched = true
        self.marked = []
    }

    /// A new scan: nothing ticked, and the defaults apply when it is done.
    func reset() {
        self.touched = false
        self.marked = []
        self.partMarks = [:]
    }

    /// The three biggest items start ticked, unless the marks were changed
    /// during the scan.
    func applyDefaults() {
        guard !self.touched else { return }
        self.marked = Set(self.scan.tally.live.prefix(3).map(\.item))
    }

    /// `item` was cleaned, so it can't be ticked any more.
    func cleaned(_ item: Item) {
        self.marked.remove(item)
    }

    // MARK: Parts

    func markedParts(of item: Item) -> Set<ItemPart> {
        self.partMarks[item] ?? []
    }

    func setMarked(_ part: ItemPart, of item: Item, _ isMarked: Bool) {
        if isMarked {
            self.partMarks[item, default: []].insert(part)
        } else {
            self.partMarks[item]?.remove(part)
        }
    }

    /// `parts` of `item` were cleaned, so they can't be ticked any more.
    func cleaned(_ parts: Set<ItemPart>, of item: Item) {
        self.partMarks[item]?.subtract(parts)
    }
}
