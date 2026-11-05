import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Worktrees screen")
struct WorktreeScreenTests {
    @Test
    func `the inspector shows the first worktree with nothing to lose until one is chosen`() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        model.screen = .worktrees
        #expect(model.currentWorktree?.name == "readme-credits-readability-9b0801")
        model.selectedWorktree = sampleWorktrees[0].path
        #expect(model.currentWorktree?.name == "portfolio-copy-typography-ec440f")
    }

    @Test
    func `the sidebar counts only what can go, and the subtitle says what stays`() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        model.screen = .worktrees
        // Two of the five have nothing to lose.
        let twoKilobytes: Int64 = 2 * 623_000
        #expect(model.removableWorktreesKilobytes == twoKilobytes)
        let twoGo = SizeText.of(kilobytes: twoKilobytes)
        let threeStay = SizeText.of(kilobytes: 3 * 623_000)
        #expect(model.subtitle == "\(twoGo) in 2 worktrees with nothing to lose. 3 more, \(threeStay), keep work, "
            + "so they stay.")

        let oneSize = SizeText.of(kilobytes: 623_000)
        let kept = sampleWorktrees[0]
        let removable = sampleWorktrees[1]
        #expect(WorktreeWords.summary([removable, kept])
            == "\(oneSize) in 1 worktree with nothing to lose. 1 more, \(oneSize), keeps work, so it stays.")
        #expect(WorktreeWords.summary([kept]) == "\(oneSize) in 1 worktree that keeps work, so it stays.")
        #expect(WorktreeWords.summary([removable, removable])
            == "\(SizeText.of(kilobytes: 2 * 623_000)) in 2 worktrees with nothing to lose.")
        #expect(WorktreeWords.summary([]) == "Nothing to remove.")
    }

    @Test
    func `with nothing to remove the sidebar's size is zero`() {
        let home = TemporaryHome()
        var extras = sampleExtras
        extras.worktrees = [sampleWorktrees[0], sampleWorktrees[3]]
        let model = makeModel(home: home, extras: extras)
        #expect(model.removableWorktreesKilobytes == 0)
    }

    @Test
    func `each worktree says what removing it does, or why it stays`() {
        func words(_ index: Int) -> String { WorktreeWords.whatHappens(sampleWorktrees[index]) }
        #expect(words(0).hasPrefix("It has 15 changes not committed. Commit or discard them"))
        var one = sampleWorktrees[0]
        one.changes = 1
        #expect(WorktreeWords.whatHappens(one).hasPrefix("It has a change not committed. Commit or discard it"))
        #expect(words(1).contains("A branch already holds its commits, so nothing committed is lost."))
        #expect(words(2).contains("The branch javi/feature-with-a-long-branch-name stays in the repository"))
        #expect(words(3).hasPrefix("It has commits on no branch"))
        #expect(words(4).hasPrefix("It's locked"))
        #expect(WorktreeWords.origin(sampleWorktrees[1]) == "portfolio, detached")
    }

    @Test
    func `a removal git refuses says why and keeps the sheet open`() async {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        let worktree = sampleWorktrees[2]
        model.worktreeToRemove = worktree
        // The model's tools have no git: the engine refuses before anything runs.
        await model.removeWorktree(worktree)
        #expect(model.worktreeToRemove == worktree)
        #expect(model.worktreeRemovalError?.hasPrefix("Git didn't remove it.") == true)
        #expect(!model.isRemovingWorktree)
    }
}
