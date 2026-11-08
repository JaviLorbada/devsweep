import DevSweepKit

/// One item's row: what state it is in, what the scan found, and, during a
/// clean, how much is gone. `ScanModel` holds one per item; only it changes them.
struct ScanRow: Identifiable {
    enum State: Equatable {
        case waiting
        case measuring
        case measured
        /// The scan stopped before reaching it.
        case notMeasured
        case cleaning
        /// Moved to the Trash or deleted; `outcome` says which.
        case cleaned
    }

    let item: Item
    var state: State = .waiting
    var result: ItemResult?
    var progressBytes: Int64 = 0
    /// While deleting, how much is gone so far.
    var removedBytes: Int64 = 0
    /// While cleaning parts of it, their size; the whole otherwise.
    var cleaningKilobytes: Int64?
    var outcome: CleanOutcome?

    /// What the last scan found, shown dimmed until this scan reaches the item.
    var previous: ItemResult?

    var id: Item {
        self.item
    }

    var kilobytes: Int64 {
        self.result?.kilobytes ?? self.progressBytes / 1024
    }

    /// While cleaning, what is still on disk, counting down as it goes.
    var leftKilobytes: Int64 {
        max(0, self.kilobytes - self.removedBytes / 1024)
    }

    /// How far deleting has got, once it has removed something; moving
    /// to the Trash takes no time and has none.
    var cleaningProgress: Double? {
        let total = self.cleaningKilobytes ?? self.kilobytes
        guard self.state == .cleaning, self.removedBytes > 0, total > 0 else { return nil }
        return min(1, Double(self.removedBytes / 1024) / Double(total))
    }

    /// The size to show now: the new size once measured, the running count
    /// while measuring, the last scan's size before that.
    var shownKilobytes: Int64 {
        switch self.state {
        case .measured, .cleaning, .cleaned: self.result?.kilobytes ?? 0
        case .measuring: self.progressBytes / 1024
        case .waiting: self.previous.map { $0.isEmpty ? 0 : $0.kilobytes } ?? 0
        case .notMeasured: 0
        }
    }

    /// Showing the last scan's size, not this scan's.
    var showsPrevious: Bool {
        self.state == .waiting && self.previous != nil
    }

    /// Being measured and already counting.
    var isCounting: Bool {
        self.state == .measuring && self.progressBytes > 0
    }

    /// The result the inspector describes: this scan's, or the last one's.
    var shownResult: ItemResult? {
        self.result ?? self.previous
    }

    /// Measured, with something to reclaim.
    var isLive: Bool {
        self.state == .measured && !(self.result?.isEmpty ?? true)
    }

    var sizeKnown: Bool {
        self.result?.sizeKnown ?? true
    }

    /// Measured at some point, whatever happened since.
    var wasMeasured: Bool {
        [.measured, .cleaning, .cleaned].contains(self.state)
    }

    var canPutBack: Bool {
        self.state == .cleaned && (self.outcome?.canPutBack ?? false)
    }
}
