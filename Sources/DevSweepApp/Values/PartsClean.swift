import DevSweepKit

/// A clean of some parts of an item, which the inspector reports and can put
/// back from the Trash.
struct PartsClean {
    let outcome: PartsCleanOutcome
    /// The item's result before, to put parts back as they were measured.
    let before: ItemResult
    /// The parts that went.
    let parts: Set<ItemPart>
    /// What is left of the item.
    let left: ItemResult
    /// What it freed, kept folders too.
    let kilobytes: Int64
    /// "2 projects", "3 folders".
    let summary: String

    init(outcome: PartsCleanOutcome, before: ItemResult) {
        self.outcome = outcome
        self.before = before
        self.parts = outcome.cleaned
        self.left = before.removing(self.parts)
        self.kilobytes = self.parts.reduce(0) { $0 + before.kilobytes(of: $1) }
        self.summary = CleanPrompt.partsSummary(self.parts, in: before.item)
    }

    var canPutBack: Bool {
        self.outcome.outcome.canPutBack
    }

    /// The item as `current` is, with the parts `putBack` brought back.
    func restoring(_ putBack: PutBackOutcome, into current: ItemResult) -> ItemResult {
        current.restoring(self.outcome.restored(by: putBack), from: self.before)
    }
}
