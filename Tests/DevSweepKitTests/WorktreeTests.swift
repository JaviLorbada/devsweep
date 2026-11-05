import Foundation
import Testing
@testable import DevSweepKit

/// A repository in the fake home's project folder, with worktrees in every
/// state git can leave one in, made with the real git.
struct WorktreeFixture {
    let home: FakeHome
    let repository: String

    /// The repository at `repository`, or at `App` in the project folder.
    init(_ home: FakeHome, at repository: String? = nil) {
        self.home = home
        self.repository = repository ?? "\(home.projects)/App"
        home.write("\(self.repository)/.gitignore", "build/\n")
        home.write("\(self.repository)/README", "App\n")
        self.git(["-C", self.repository, "init", "-q", "-b", "main"])
        self.git(["-C", self.repository, "add", ".gitignore", "README"])
        self.commit(in: self.repository, "First")
    }

    /// Runs git as the fake home's user, with a fixed identity and no
    /// signing, so the machine's own git settings don't matter.
    func git(_ arguments: [String]) {
        self.home.git(
            ["-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false"] + arguments,
            environment: self.home.environment)
    }

    func commit(in folder: String, _ message: String) {
        self.git(["-C", folder, "commit", "-q", "--allow-empty", "-m", message])
    }

    /// `git worktree add`, with a new branch or detached.
    @discardableResult
    func add(_ path: String, branch: String?) -> String {
        self
            .git(["-C", self.repository, "worktree", "add", "-q"] + (branch.map { ["-b", $0] } ?? ["--detach"]) +
                [path])
        return path
    }
}

@Suite("Git worktrees")
struct WorktreeTests {
    @Test
    func `worktrees are found through git wherever they live, with what would be lost`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let fixture = WorktreeFixture(home)
        // Kept by a tool in a hidden folder of its own, outside the project folder.
        let clean = fixture.add(home.path(".tool/worktrees/clean"), branch: "clean")
        home.fill("\(clean)/build/output")
        let changed = fixture.add("\(fixture.repository)/.tool/worktrees/changed", branch: "changed")
        home.write("\(changed)/notes.txt", "draft\n")
        let detached = fixture.add(home.path(".tool/worktrees/detached"), branch: nil)
        fixture.commit(in: detached, "Only here")
        fixture.add(home.path(".tool/worktrees/detached-at-main"), branch: nil)
        let locked = fixture.add(home.path(".tool/worktrees/locked"), branch: "locked")
        fixture.git(["-C", fixture.repository, "worktree", "lock", locked])

        let worktrees = try await engine(home, tools).extras().worktrees
        let byName = Dictionary(uniqueKeysWithValues: worktrees.map { ($0.name, $0) })
        #expect(Set(byName.keys) == ["clean", "changed", "detached", "detached-at-main", "locked"])
        #expect(worktrees.allSatisfy { FileSystem.basename($0.repository) == "App" })

        let cleanOne = try #require(byName["clean"])
        #expect(cleanOne.branch == "clean" && cleanOne.changes == 0 && cleanOne.keptBecause == nil)
        #expect(cleanOne.kilobytes > 0 && cleanOne.lastCommit != nil)
        // The ignored build folder isn't a change; the untracked notes are.
        #expect(byName["changed"]?.keptBecause == "1 change not committed")
        #expect(byName["detached"]?.branch == nil)
        #expect(byName["detached"]?.keptBecause == "Commits on no branch")
        // Detached at a commit main holds: nothing to lose.
        #expect(byName["detached-at-main"]?.keptBecause == nil)
        #expect(byName["locked"]?.keptBecause == "Locked")
        // The repository's own working copy is never listed as one.
        #expect(byName["App"] == nil)
    }

    @Test
    func `under the original script's name no worktrees are listed and git isn't asked`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let fixture = WorktreeFixture(home)
        fixture.add(home.path(".tool/worktrees/clean"), branch: "clean")
        var config = ScanConfig.fromEnvironment(home.environment, command: .original)
        config.environment = home.environment
        #expect(!config.includeWorktrees)
        let extras = try await Engine(config: config, tools: tools.tools).extras()
        #expect(extras.worktrees.isEmpty)
        #expect(!tools.log.calls.contains { $0.contains("worktree") })
    }

    @Test
    func `removing a worktree with nothing to lose runs git's own command and keeps its branch`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let fixture = WorktreeFixture(home)
        let clean = fixture.add(home.path(".tool/worktrees/clean"), branch: "clean")
        home.fill("\(clean)/build/output")
        let engine = try engine(home, tools)
        let worktree = try #require(await engine.extras().worktrees.first)

        #expect(await engine.removeWorktree(worktree))
        #expect(!home.exists(clean))
        // With the path as git lists it, which may resolve symlinks HOME goes through.
        #expect(tools.log.calls.contains {
            $0.hasPrefix("git -C \(worktree.repository) worktree remove /") && $0.hasSuffix("/.tool/worktrees/clean")
        })
        #expect(home.exists("\(fixture.repository)/.git/refs/heads/clean"))
        #expect(await engine.extras().worktrees.isEmpty)
    }

    @Test
    func `a worktree with changes, commits on no branch or a lock stays, and git is never asked`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let fixture = WorktreeFixture(home)
        let changed = fixture.add(home.path(".tool/worktrees/changed"), branch: "changed")
        home.write("\(changed)/notes.txt", "draft\n")
        let detached = fixture.add(home.path(".tool/worktrees/detached"), branch: nil)
        fixture.commit(in: detached, "Only here")
        let locked = fixture.add(home.path(".tool/worktrees/locked"), branch: "locked")
        fixture.git(["-C", fixture.repository, "worktree", "lock", locked])
        let engine = try engine(home, tools)

        let worktrees = await engine.extras().worktrees
        #expect(worktrees.count == 3)
        for worktree in worktrees {
            #expect(await !engine.removeWorktree(worktree), "\(worktree.name)")
            #expect(home.exists(worktree.path))
        }
        #expect(!tools.log.calls.contains { $0.contains("worktree remove") })
    }

    @Test
    func `a worktree that changed since it was listed is checked again, and kept`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let fixture = WorktreeFixture(home)
        let clean = fixture.add(home.path(".tool/worktrees/clean"), branch: "clean")
        let engine = try engine(home, tools)
        let worktree = try #require(await engine.extras().worktrees.first)
        #expect(worktree.keptBecause == nil)

        home.write("\(clean)/notes.txt", "draft\n")
        #expect(await !engine.removeWorktree(worktree))
        #expect(home.exists(clean))
        // Nor a folder git doesn't list as one of the repository's worktrees.
        var stranger = worktree
        stranger.path = home.fill(home.path("Workspace/Other"))
        #expect(await !engine.removeWorktree(stranger))
        #expect(home.exists(stranger.path))
    }

    @Test
    func `worktree paths read from HOME as given, so they shorten to the tilde`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let fixture = WorktreeFixture(home)
        fixture.add(home.path(".tool/worktrees/clean"), branch: "clean")
        let engine = try engine(home, tools)
        let worktree = try #require(await engine.extras().worktrees.first)
        // The temp folder the fake home is in goes through a symlink, as /var does.
        #expect(engine.policy.tilde(worktree.path) == "~/.tool/worktrees/clean")
        #expect(engine.policy.tilde(worktree.repository) == "~/Workspace/App")
    }

    @Test
    func `worktrees outside the home folder aren't listed`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let fixture = WorktreeFixture(home)
        fixture.add(home.outside("elsewhere"), branch: "elsewhere")
        #expect(try await engine(home, tools).extras().worktrees.isEmpty)
    }

    @Test
    func `a project folder of worktrees leads to their repository, wherever it is`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        // Only the folder a tool keeps its worktrees in is a project folder.
        let fixture = WorktreeFixture(home, at: home.path("Elsewhere/Tool"))
        fixture.add(home.path(".tool/worktrees/ab12/Tool"), branch: nil)
        fixture.add(home.path(".tool/worktrees/cd34/Tool"), branch: "fix")
        let engine = try engine(home, tools, projects: [home.path(".tool/worktrees")])

        let worktrees = await engine.extras().worktrees
        #expect(Set(worktrees.map(\.name)) == ["ab12/Tool", "cd34/Tool"])
        #expect(worktrees.allSatisfy { engine.policy.tilde($0.repository) == "~/Elsewhere/Tool" })
        // Git is asked of the repository, once, not of each worktree.
        #expect(tools.log.calls.filter { $0.hasSuffix(" worktree list --porcelain") }.count == 1)
    }

    @Test
    func `a repository found in a project folder and through its worktrees is asked once`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let fixture = WorktreeFixture(home)
        fixture.add(home.path(".tool/worktrees/one"), branch: "one")
        fixture.add(home.path(".tool/worktrees/two"), branch: "two")
        let engine = try engine(home, tools, projects: [home.projects, home.path(".tool/worktrees")])

        #expect(await engine.extras().worktrees.map(\.name).sorted() == ["one", "two"])
        #expect(tools.log.calls.filter { $0.hasSuffix(" worktree list --porcelain") }.count == 1)
    }

    @Test
    func `worktrees of a bare repository lead back to it`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let fixture = WorktreeFixture(home, at: home.path("Elsewhere/Source"))
        let bare = home.path("Elsewhere/App.git")
        fixture.git(["clone", "-q", "--bare", fixture.repository, bare])
        fixture.git(["-C", bare, "worktree", "add", "-q", "-b", "feature", home.path(".tool/worktrees/feature")])
        let engine = try engine(home, tools, projects: [home.path(".tool/worktrees")])

        let worktree = try #require(await engine.extras().worktrees.first)
        #expect(worktree.name == "feature" && worktree.branch == "feature")
        #expect(engine.policy.tilde(worktree.repository) == "~/Elsewhere/App.git")
    }

    @Test
    func `a worktree whose repository is outside the home folder isn't listed`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let fixture = WorktreeFixture(home, at: home.outside("Outside/App"))
        fixture.add(home.path(".tool/worktrees/away"), branch: "away")

        #expect(try await engine(home, tools, projects: [home.path(".tool/worktrees")]).extras().worktrees.isEmpty)
        #expect(!tools.log.calls.contains { $0.contains(" worktree list") })
    }

    @Test
    func `only a worktree's .git file leads to a repository`() throws {
        let home = FakeHome()
        // A relative gitdir, as git writes one with worktree.useRelativePaths.
        home.mkdir(home.path("Repo/.git/worktrees/w"))
        home.write(home.path("Repo/.git/worktrees/w/commondir"), "../..\n")
        home.write(home.path("w/.git"), "gitdir: ../Repo/.git/worktrees/w\n")
        let repository = try #require(FileSystem.physicalDirectory(home.path("Repo")))
        #expect(WorktreeScanner.repository(ofWorktree: home.path("w")) == repository)
        // A submodule's names a folder under modules.
        home.mkdir(home.path("Repo/.git/modules/lib"))
        home.write(home.path("Repo/lib/.git"), "gitdir: ../.git/modules/lib\n")
        #expect(WorktreeScanner.repository(ofWorktree: home.path("Repo/lib")) == nil)
        // A worktree whose repository is gone leads nowhere.
        home.write(home.path("orphan/.git"), "gitdir: \(home.path("Gone/.git/worktrees/orphan"))\n")
        #expect(WorktreeScanner.repository(ofWorktree: home.path("orphan")) == nil)
    }

    @Test
    func `a worktree named like its repository is told apart by its parent folder`() {
        func named(_ path: String) -> String {
            GitWorktree(
                path: path,
                repository: "/h/Workspace/App",
                branch: nil,
                kilobytes: 0,
                lastCommit: nil,
                changes: 0,
                commitsKept: true,
                isLocked: false).name
        }
        #expect(named("/h/.tool/worktrees/fix-login/App") == "fix-login/App")
        #expect(named("/h/Workspace/App/.tool/worktrees/fix-login") == "fix-login")
    }

    @Test
    func `git's porcelain listing is read entry by entry`() {
        let listing = """
        worktree /r/App
        HEAD 1111
        branch refs/heads/main

        worktree /r/wt/one
        HEAD 2222
        branch refs/heads/feature/one
        locked reason here

        worktree /r/wt/two
        HEAD 3333
        detached

        worktree /r/wt/gone
        HEAD 4444
        detached
        prunable gitdir file points to non-existent location

        """
        #expect(WorktreeScanner.parse(listing) == [
            .init(path: "/r/App", branch: "main"),
            .init(path: "/r/wt/one", branch: "feature/one", isLocked: true),
            .init(path: "/r/wt/two", branch: nil),
            .init(path: "/r/wt/gone", branch: nil, isPrunable: true),
        ])
    }

    @Test
    func `devsweep's report lists worktrees with the command to remove them, and devclean's doesn't`() throws {
        let home = FakeHome()
        let policy = try PathPolicy(home: home.home)
        func worktree(_ name: String, changes: Int) -> GitWorktree {
            GitWorktree(
                path: home.path("Workspace/App/.tool/worktrees/\(name)"),
                repository: home.path("Workspace/App"),
                branch: name,
                kilobytes: 2048,
                lastCommit: Date(timeIntervalSince1970: 1_792_000_000),
                changes: changes,
                commitsKept: true,
                isLocked: false)
        }
        let extras = Extras(worktrees: [worktree("clean", changes: 0), worktree("busy", changes: 3)])
        let report = Report.extras(extras, staleDays: 90, policy: policy, command: .product)
        #expect(report.contains("Git worktrees\n"))
        #expect(report.contains("App, branch clean, last commit 2026-10-14"))
        #expect(report.contains(
            "Nothing to lose. Remove with: git -C ~/Workspace/App worktree remove "
                + "~/Workspace/App/.tool/worktrees/clean"))
        #expect(report.contains("3 changes not committed, so it stays."))
        #expect(!Report.extras(extras, staleDays: 90, policy: policy, command: .original).contains("worktree"))
    }

    @Test
    func `a path the shell would change is quoted in the command`() throws {
        let home = FakeHome()
        let policy = try PathPolicy(home: home.home)
        #expect(ShellWord.path(home.path("Work/App"), policy: policy) == "~/Work/App")
        #expect(ShellWord.path(home.path("My Work/App"), policy: policy) == "'\(home.home)/My Work/App'")
        #expect(ShellWord.quoted("it's") == #"'it'\''s'"#)
    }

    @Test
    func `a scan saved before worktrees were listed reads with none`() throws {
        let json = Data(#"{"xcodes":[],"runtimes":[]}"#.utf8)
        #expect(try JSONDecoder().decode(Extras.self, from: json).worktrees.isEmpty)
    }
}

/// An engine whose project folders are `projects`, in place of the fake
/// home's Workspace.
private func engine(_ home: FakeHome, _ tools: FakeTools, projects: [String]) throws -> Engine {
    var config = ScanConfig.fromEnvironment(home.environment)
    config.environment = home.environment
    config.projectDirectories = projects
    return try Engine(config: config, tools: tools.tools, measurer: SizeMeasurer(progressInterval: 2))
}
