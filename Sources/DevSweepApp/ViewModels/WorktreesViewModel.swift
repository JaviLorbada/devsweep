import DevSweepKit
import Observation

/// The worktrees screen's own state: the worktree selected, the removal
/// sheet, and what the screen says under its title.
@MainActor
@Observable
final class WorktreesViewModel {
    /// The worktree selected, by its path.
    private(set) var selectedPath: String?
    let removal = Removal<GitWorktree>()
    private let scan: any Listings

    init(scan: any Listings) {
        self.scan = scan
    }

    var worktrees: [GitWorktree] {
        self.scan.extras?.worktrees ?? []
    }

    /// The selected worktree, or the first with nothing to lose, or the first.
    var current: GitWorktree? {
        self.worktrees.first { $0.path == self.selectedPath }
            ?? self.worktrees.first { $0.keptBecause == nil }
            ?? self.worktrees.first
    }

    func select(_ worktree: GitWorktree) {
        self.selectedPath = worktree.path
    }

    /// Selects `worktree` and opens the removal sheet for it.
    func askToRemove(_ worktree: GitWorktree) {
        self.select(worktree)
        self.removal.ask(worktree)
    }

    /// Removes the worktree on the sheet with git, then lists worktrees again.
    func remove(_ worktree: GitWorktree) async {
        let removed = await self.removal.run(
            worktree,
            failure: "Git didn't remove it. It may have changed since it was listed, or hold a submodule; run the "
                + "command in Terminal to see why.",
            remove: self.scan.removeWorktree)
        if removed { self.selectedPath = nil }
    }

    /// The git command that removes `worktree`, to run in Terminal.
    func removalCommand(for worktree: GitWorktree) -> String {
        self.scan.policy.map { worktree.removalCommand(policy: $0) } ?? ""
    }

    var subtitle: String {
        StatusText.worktrees(self.scan.extras?.worktrees, isLoading: self.scan.isLoadingExtras)
    }
}
