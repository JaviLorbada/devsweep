import Observation

/// One removal sheet's state: what is waiting on it, whether the removal is
/// running, and why it failed. The runtimes and the worktrees screens each
/// keep one.
@MainActor
@Observable
final class Removal<Thing: Identifiable> {
    /// What the sheet asks about; the sheet shows while it is set and
    /// closing it clears it.
    var pending: Thing?
    private(set) var isRemoving = false
    private(set) var error: String?

    /// Opens the sheet for `thing`.
    func ask(_ thing: Thing) {
        self.pending = thing
    }

    /// The sheet is asked again, without the last failure.
    func clearError() {
        self.error = nil
    }

    /// Removes `thing` with `remove`. On success the sheet closes; otherwise
    /// it stays open with `failure`. Whether it was removed.
    @discardableResult
    func run(_ thing: Thing, failure: String, remove: @MainActor (Thing) async -> Bool) async -> Bool {
        guard !self.isRemoving else { return false }
        self.isRemoving = true
        self.error = nil
        let removed = await remove(thing)
        self.isRemoving = false
        if removed {
            self.pending = nil
        } else {
            self.error = failure
        }
        return removed
    }
}
