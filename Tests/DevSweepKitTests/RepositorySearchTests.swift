import Foundation
import Testing
@testable import DevSweepKit

/// A build folder that holds a git repository is kept: the project's
/// repository ignores the folder, so it can't see the edits or commits of a
/// dependency cloned into it. Run as devclean, the folders are the script's.
@Suite("Build folders holding a git repository")
struct RepositorySearchTests {
    /// Each item, its folder, and the file that has to sit next to it.
    static let kinds: [(item: Item, folder: String, file: String)] = [
        (.swiftpmBuilds, ".build", "Package.swift"),
        (.gradleBuilds, "build", "build.gradle"),
        (.cocoapodsPods, "Pods", "Podfile.lock"),
        (.cargoBuilds, "target", "Cargo.toml"),
        (.nodeModules, "node_modules", "package.json"),
    ]

    @Test(arguments: kinds)
    func `a .git of any kind, at any depth, keeps the folder with a warning`(
        _ kind: (item: Item, folder: String, file: String)) async throws
    {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        // The projects' repository tracks nothing in their build folders.
        home.mkdir("\(p)/.git")
        tools.gitAnswer = { _, _ in "" }
        for project in ["Clean", "Cloned", "Linked", "Worktree"] {
            home.touch("\(p)/\(project)/\(kind.file)")
            home.fill("\(p)/\(project)/\(kind.folder)")
        }
        home.fill("\(p)/Cloned/\(kind.folder)/lib/dependency/.git")
        home.symlink(home.outside("missing"), at: "\(p)/Linked/\(kind.folder)/.git")
        home.write("\(p)/Worktree/\(kind.folder)/dependency/.git", "gitdir: /elsewhere\n")

        let engine = try engine(home, tools, includeExtras: false)
        let events = await collect(engine)
        let result = try #require(events.result(kind.item))
        let projects = "\(engine.policy.homeReal)/Workspace"
        let clean = "\(projects)/Clean/\(kind.folder)"
        #expect(result.paths == [clean])
        let folders = try #require(result.folderKilobytes)
        #expect(folders.keys.sorted() == [clean])
        #expect(result.kilobytes == folders[clean])
        #expect(events.warnings == [
            "Skipped \(projects)/Cloned/\(kind.folder): it holds a git repository, lib/dependency.",
            "Skipped \(projects)/Linked/\(kind.folder): it is a git repository.",
            "Skipped \(projects)/Worktree/\(kind.folder): it holds a git repository, dependency.",
        ])
    }

    @Test
    func `an Xcode build folder holding a .git is kept too`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.touch("\(p)/App/Package.swift")
        home.fillXcodeBuild("\(p)/App/build")
        home.mkdir("\(p)/App/build/Tool/.git")

        let engine = try engine(home, tools, includeExtras: false)
        let events = await collect(engine)
        #expect(events.result(.xcodeBuilds)?.paths == [])
        #expect(events.warnings == [
            "Skipped \(engine.policy.homeReal)/Workspace/App/build: it holds a git repository, Tool.",
        ])
    }

    @Test
    func `devsweep --run deletes the clean folder and keeps the one holding a clone`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        for project in ["Clean", "Cloned"] {
            home.touch("\(p)/\(project)/package.json")
            home.fill("\(p)/\(project)/node_modules")
        }
        home.fill("\(p)/Cloned/node_modules/dependency/.git")

        let terminal = BufferTerminal()
        let status = await CommandLineSession.run(
            CommandLineOptions(run: true, yes: true, skip: "homebrew,simulators"),
            environment: home.environment,
            tools: tools.tools,
            terminal: terminal,
            command: .product)

        #expect(status == 0)
        #expect(!home.exists("\(p)/Clean/node_modules"))
        #expect(home.isFile("\(p)/Cloned/node_modules/dependency/.git/file"))
        let projects = try "\(PathPolicy(home: home.home).homeReal)/Workspace"
        #expect(terminal.standardError.contains(
            "Skipped \(projects)/Cloned/node_modules: it holds a git repository, dependency.\n"))
    }

    @Test
    func `devclean lists them, as the script does`() async {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.touch("\(p)/App/Package.swift")
        home.fill("\(p)/App/.build")
        home.fill("\(p)/App/.build/lib/dependency/.git")

        let run = await devclean(home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("SwiftPM .build folders (1)"))
        #expect(!run.output.contains("git repository"))
    }

    @Test
    func `measuring stops at the repository and counts nothing`() {
        let home = FakeHome()
        let folder = home.fill(home.path("Workspace/App/node_modules"))
        home.writeZeros("\(folder)/big", kilobytes: 64)
        home.fill("\(folder)/dependency/.git")

        let measured = SizeMeasurer().measure(folder, search: RepositorySearch(), progress: nil)
        #expect(measured.repository == "\(folder)/dependency")
        #expect(measured.kilobytes == 0)
        #expect(SizeMeasurer().measure(folder).repository == nil)
    }
}
