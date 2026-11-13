import Darwin
import Foundation
import Synchronization
import Testing
@testable import DevSweepKit

@Suite("Path policy")
struct PathPolicyTests {
    @Test
    func `home is resolved once, and must be an absolute folder other than /`() throws {
        let home = FakeHome()
        let policy = try PathPolicy(home: home.home)
        #expect(policy.homeReal.hasPrefix("/private/var/") || !home.home.hasPrefix("/var/"))
        #expect(policy.homeReal == FileSystem.physicalDirectory(home.home))
        #expect(throws: PreflightError.badHome) { try PathPolicy(home: "/") }
        #expect(throws: PreflightError.badHome) { try PathPolicy(home: "") }
        #expect(throws: PreflightError.badHome) { try PathPolicy(home: "relative/home") }
        #expect(throws: PreflightError.badHome) { try PathPolicy(home: home.path("missing")) }
        home.touch(home.path("file"))
        #expect(throws: PreflightError.badHome) { try PathPolicy(home: home.path("file")) }
        #expect(throws: PreflightError.runningAsRoot) { try PathPolicy.preflight(home: home.home, effectiveUserID: 0) }
    }

    @Test
    func `only real folders strictly inside home pass`() throws {
        let home = FakeHome()
        let policy = try PathPolicy(home: home.home)
        home.fill(home.path("inside"))
        home.fill(home.outside("outside"))
        home.symlink(home.path("inside"), at: home.path("link-to-inside"))
        home.symlink(home.outside("outside"), at: home.path("link-to-outside"))
        home.touch(home.path("a-file"))

        #expect(policy.safePath(home.path("inside")) == "\(policy.homeReal)/inside")
        #expect(policy.safePath(home.home) == nil)
        #expect(policy.safePath(home.path(".")) == nil)
        #expect(policy.safePath(home.path("inside/..")) == nil)
        #expect(policy.safePath(home.path("../outside")) == nil)
        #expect(policy.safePath(home.outside("outside")) == nil)
        #expect(policy.safePath(home.path("link-to-inside")) == nil)
        #expect(policy.safePath(home.path("link-to-outside")) == nil)
        #expect(policy.safePath(home.path("link-to-outside/file")) == nil)
        #expect(policy.safePath(home.path("a-file")) == nil)
        #expect(policy.safePath(home.path("missing")) == nil)
    }

    @Test
    func `A sibling whose name starts with home's name is outside`() throws {
        let home = FakeHome()
        let policy = try PathPolicy(home: home.home)
        home.fill(home.outside("home2/cache"))
        #expect(policy.safePath(home.outside("home2/cache")) == nil)
        #expect(!policy.isStrictlyInsideHome("\(policy.homeReal)2/cache"))
        #expect(!policy.isStrictlyInsideHome("\(policy.homeReal)/"))
    }

    @Test
    func `A path is still safe only while it resolves to exactly itself`() throws {
        let home = FakeHome()
        let policy = try PathPolicy(home: home.home)
        home.fill(home.path("Library/Caches/thing"))
        let real = try #require(policy.safePath(home.path("Library/Caches/thing")))
        #expect(policy.stillSafe(real))

        try FileManager.default.moveItem(atPath: home.path("Library/Caches"), toPath: home.outside("moved"))
        home.symlink(home.outside("moved"), at: home.path("Library/Caches"))
        #expect(!policy.stillSafe(real))
    }

    @Test
    func `~ shortens and expands against HOME as given`() throws {
        let home = FakeHome()
        let policy = try PathPolicy(home: home.home)
        #expect(policy.tilde(home.home) == "~")
        #expect(policy.tilde(home.path("Library/Caches")) == "~/Library/Caches")
        #expect(policy.tilde("\(home.home)2/x") == "\(home.home)2/x")
        #expect(policy.tilde(policy.homeReal + "/x") == policy.homeReal + "/x")
        #expect(policy.expandTilde("~/Workspace") == home.path("Workspace"))
        #expect(policy.expandTilde("~") == home.home)
        #expect(policy.expandTilde("/a/~") == "/a/~")
    }

    @Test
    func `project folders are found, missing, or outside home`() throws {
        let home = FakeHome()
        let policy = try PathPolicy(home: home.home)
        home.mkdir(home.outside("elsewhere"))
        home.symlink(home.outside("elsewhere"), at: home.path("Code"))
        let folders = policy.projectFolders([home.projects, "~/Missing", home.path("Code"), "~", ""])
        #expect(folders.found == ["~/Workspace", "~"])
        #expect(folders.missing == ["~/Missing"])
        #expect(folders.outside == ["~/Code"])
        #expect(folders.roots == ["\(policy.homeReal)/Workspace", policy.homeReal])
    }
}

@Suite("Git tracking")
struct GitTrackingTests {
    func check(
        _ folder: String,
        home: FakeHome,
        environment: [String: String] = [:],
        git: any GitClient) async throws -> (Bool, [String])
    {
        let policy = try PathPolicy(home: home.home)
        var warnings: [String] = []
        let untracked = await GitTracking.isUntracked(
            folder, environment: environment, git: git, policy: policy, warn: { warnings.append($0) })
        return (untracked, warnings)
    }

    @Test
    func `without any .git up the tree, git is never asked`() async throws {
        let home = FakeHome(), log = CallLog()
        home.fill(home.path("Workspace/App/.build"))
        let (untracked, warnings) = try await check(
            home.path("Workspace/App/.build"),
            home: home,
            git: FakeGit(log: log) { _, _ in "tracked" })
        #expect(untracked)
        #expect(warnings.isEmpty)
        #expect(log.calls.isEmpty)
    }

    @Test
    func `git's answer decides when a .git exists, and any failure keeps the folder`() async throws {
        let home = FakeHome(), log = CallLog()
        home.fill(home.path("Workspace/App/.build"))
        home.mkdir(home.path("Workspace/.git"))
        let folder = home.path("Workspace/App/.build")

        #expect(try await self.check(folder, home: home, git: FakeGit(log: log) { _, _ in "" }).0)
        #expect(try await !self.check(folder, home: home, git: FakeGit(log: log) { _, _ in ".build/file" }).0)
        let (untracked, warnings) = try await check(folder, home: home, git: FakeGit(log: log) { _, _ in nil })
        #expect(!untracked)
        #expect(warnings == ["Skipped ~/Workspace/App/.build: couldn't check whether git tracks it."])
        #expect(log.calls.first == "git -C \(home.path("Workspace/App")) ls-files -- .build")
    }

    @Test
    func `GIT_DIR or GIT_WORK_TREE alone is enough to ask git`() async throws {
        let home = FakeHome(), log = CallLog()
        home.fill(home.path("Workspace/App/.build"))
        let git = FakeGit(log: log) { _, _ in nil }
        #expect(try await !self.check(
            home.path("Workspace/App/.build"),
            home: home,
            environment: ["GIT_DIR": "/x"],
            git: git).0)
        #expect(try await !self.check(
            home.path("Workspace/App/.build"),
            home: home,
            environment: ["GIT_WORK_TREE": "/x"],
            git: git).0)
        #expect(try await self.check(
            home.path("Workspace/App/.build"),
            home: home,
            environment: ["GIT_DIR": ""],
            git: git).0)
    }

    @Test
    func `A missing git binary keeps the folder`() async throws {
        let home = FakeHome()
        home.fill(home.path("Workspace/App/.build"))
        home.mkdir(home.path("Workspace/App/.git"))
        let git = LiveGitClient(runner: LiveProcessRunner(environment: ["PATH": home.path("empty-bin")]))
        let (untracked, warnings) = try await check(home.path("Workspace/App/.build"), home: home, git: git)
        #expect(!untracked)
        #expect(warnings.count == 1)
    }
}

@Suite("Running tools")
struct ProcessRunnerTests {
    @Test
    func `tools are found through the environment's PATH and run in the C locale`() async throws {
        let runner = LiveProcessRunner(environment: ["PATH": "/nonexistent:/usr/bin:/bin", "LC_ALL": "es_ES.UTF-8"])
        #expect(runner.locate("env") == "/usr/bin/env")
        #expect(runner.locate("no-such-tool-anywhere") == nil)
        let output = try #require(await runner.run("env", []))
        #expect(output.succeeded)
        #expect(output.text.split(separator: "\n").contains("LC_ALL=C"))
    }

    @Test
    func `A tool that isn't installed is reported, not run`() async {
        let runner = LiveProcessRunner(environment: ["PATH": "/nonexistent"])
        #expect(await runner.run("xcrun", []) == nil)
        #expect(!LiveSimctlClient(runner: runner).isAvailable)
        #expect(!LiveBrewClient(runner: runner).isAvailable)
        #expect(await LiveSimctlClient(runner: runner).deleteUnavailable() == false)
    }
}

@Suite("Measuring")
struct MeasuringTests {
    func du(_ path: String) -> Int64 {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        must { try process.run() }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return Int64(output.split(separator: "\t").first ?? "0") ?? 0
    }

    @Test
    func `sizes match du -sk, counting hard links once and never following symlinks`() {
        let home = FakeHome()
        let tree = home.path("tree")
        home.fill("\(tree)/a/b/c")
        home.writeZeros("\(tree)/big", kilobytes: 1500)
        home.writeZeros("\(tree)/a/odd", kilobytes: 3)
        link("\(tree)/big", "\(tree)/a/hardlink")
        home.writeZeros(home.outside("elsewhere/huge"), kilobytes: 5000)
        home.symlink(home.outside("elsewhere"), at: "\(tree)/a/link")
        home.symlink("missing", at: "\(tree)/broken")

        let measured = SizeMeasurer(progressInterval: 2).measure(tree)
        #expect(measured.kilobytes == self.du(tree))
        #expect(measured.readable)
        #expect(SizeMeasurer().measure("\(tree)/a/link").kilobytes == self.du("\(tree)/a/link"))
        #expect(SizeMeasurer().measure(home.path("missing")).kilobytes == 0)
    }

    @Test
    func `progress reports a running total that ends at the size`() {
        let home = FakeHome()
        for n in 0..<20 {
            home.writeZeros(home.path("tree/f\(n)"), kilobytes: 8)
        }
        let totals = Mutex<[Int64]>([])
        let measured = SizeMeasurer(progressInterval: 5).measure(home.path("tree")) { bytes in
            totals.withLock { $0.append(bytes) }
        }
        let reported = totals.withLock { $0 }
        #expect(reported.count >= 4)
        #expect(reported == reported.sorted())
        #expect(reported.last == measured.kilobytes * 1024)
    }

    @Test
    func `A folder that can't be read has an unknown size`() {
        let home = FakeHome()
        home.fill(home.path("locked"))
        chmod(home.path("locked"), 0)
        defer { chmod(home.path("locked"), 0o755) }
        let measured = SizeMeasurer().measure(home.path("locked"))
        #expect(!measured.readable)
        #expect(measured.kilobytes == 0)
    }

    @Test
    func `free space matches df -k`() throws {
        let home = FakeHome()
        let space = try #require(DiskSpace.of(home.home))
        #expect(space.availableKilobytes > 0)
        #expect(space.totalKilobytes >= space.availableKilobytes)
        #expect(DiskSpace.of(home.path("missing")) == nil)
    }

    @Test
    func `macOS's available figure is read only when asked for, so the report stays df's`() throws {
        let home = FakeHome()
        #expect(try #require(DiskSpace.of(home.home)).availableIncludingPurgeableKilobytes == nil)
        let space = try #require(DiskSpace.of(home.home, includingPurgeable: true))
        let available = try #require(space.availableIncludingPurgeableKilobytes)
        #expect(available > 0 && available <= space.totalKilobytes)
    }
}
