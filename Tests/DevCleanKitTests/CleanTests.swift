import Foundation
import Testing
@testable import DevCleanKit

@Suite("Cleaning")
struct CleanTests {
    func scanned(_ item: Item, _ engine: Engine) async throws -> ItemResult {
        try #require(await collect(engine).result(item))
    }

    @Test("Trash mode moves each folder to the Trash and Put back restores it")
    func trashAndPutBack() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path("Library/Caches/CocoaPods"))
        home.fill(home.path("Library/Caches/Sourcery"))
        let engine = try engine(home, tools)
        let result = try await scanned(.toolCaches, engine)

        let outcome = await engine.clean(result, mode: .trash)
        #expect(outcome.removed.count == 2)
        #expect(outcome.canPutBack)
        #expect(outcome.warnings.isEmpty)
        #expect(!home.exists(home.path("Library/Caches/CocoaPods")))
        for removed in outcome.removed {
            #expect(home.exists(try #require(removed.trashed)))
        }

        let putBack = await engine.putBack(outcome)
        #expect(putBack.failed.isEmpty)
        #expect(putBack.restored.count == 2)
        #expect(home.isFile(home.path("Library/Caches/CocoaPods/file")))
        #expect(home.isFile(home.path("Library/Caches/Sourcery/file")))
    }

    @Test("Put back never replaces something that took the folder's place")
    func putBackKeepsReplacement() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path(".npm/_cacache"))
        let engine = try engine(home, tools)
        let outcome = await engine.clean(try await scanned(.npmCache, engine), mode: .trash)
        home.write(home.path(".npm/_cacache/new"), "new\n")

        let putBack = await engine.putBack(outcome)
        #expect(putBack.restored.isEmpty)
        #expect(putBack.failed == outcome.removed.map(\.original))
        #expect(home.isFile(home.path(".npm/_cacache/new")))
        #expect(!home.exists(home.path(".npm/_cacache/file")))
    }

    @Test("Put back refuses when the parent now leads outside home")
    func putBackRechecksParent() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path("Library/Caches/CocoaPods"))
        let engine = try engine(home, tools)
        let outcome = await engine.clean(try await scanned(.toolCaches, engine), mode: .trash)
        try FileManager.default.moveItem(atPath: home.path("Library/Caches"), toPath: home.outside("moved"))
        home.symlink(home.outside("moved"), at: home.path("Library/Caches"))

        let putBack = await engine.putBack(outcome)
        #expect(putBack.restored.isEmpty)
        #expect(!home.exists(home.outside("moved/CocoaPods")))
    }

    @Test("Trash mode rechecks each path like delete mode")
    func trashRechecks() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path("Library/Caches/org.swift.swiftpm"))
        let engine = try engine(home, tools)
        let result = try await scanned(.swiftpmCache, engine)
        try FileManager.default.moveItem(atPath: home.path("Library/Caches"), toPath: home.outside("moved"))
        home.symlink(home.outside("moved"), at: home.path("Library/Caches"))

        let outcome = await engine.clean(result, mode: .trash)
        #expect(outcome.removed.isEmpty)
        #expect(outcome.skipped == result.paths)
        #expect(outcome.warnings.first?.contains("changed since the scan") == true)
        #expect(home.isFile(home.outside("moved/org.swift.swiftpm/file")))
        #expect(!tools.log.calls.contains { $0.hasPrefix("trash") })
    }

    @Test("Simulators and Homebrew go through their tools in either mode, and failures warn")
    func toolItems() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.simctlDeleteSucceeds = false
        tools.brewCleanupSucceeds = false
        let engine = try engine(home, tools)
        let simulators = ItemResult(item: .simulators, paths: [], kilobytes: 4, location: "")
        let homebrew = ItemResult(item: .homebrew, paths: [], kilobytes: 4, location: "")

        let first = await engine.clean(simulators, mode: .trash)
        #expect(first.toolSucceeded == false)
        #expect(first.warnings == ["Couldn't delete unavailable simulators."])
        #expect(!first.canPutBack)
        let second = await engine.clean(homebrew, mode: .delete)
        #expect(second.warnings == ["brew cleanup failed. Run it yourself to see why."])
        #expect(tools.log.contains("xcrun simctl delete unavailable"))
        #expect(tools.log.contains("brew cleanup --prune=all"))
    }

    @Test("Paths already gone are skipped quietly")
    func alreadyGone() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let engine = try engine(home, tools)
        let result = ItemResult(item: .npmCache, paths: [engine.policy.homeReal + "/.npm/_cacache"], kilobytes: 4, location: "")
        let outcome = await engine.clean(result, mode: .delete)
        #expect(outcome.removed.isEmpty && outcome.skipped.isEmpty && outcome.warnings.isEmpty)
    }
}

@Suite("Command line session")
struct SessionTests {
    @Test("The prompt deletes only on y, Y, yes or YES")
    func prompt() async {
        for (answer, deletes) in [("y", true), ("YES", true), ("  yes  ", true), ("Yes", false), ("n", false), ("", false)] {
            let home = FakeHome(), tools = FakeTools(home: home)
            home.fill(home.path("Library/Caches/org.swift.swiftpm"))
            let run = await devclean("--run", home: home, tools: tools, input: [answer])
            #expect(run.status == 0)
            #expect(run.standardOutput.contains("Delete 4 KB? [y/N] "))
            #expect(home.exists(home.path("Library/Caches/org.swift.swiftpm")) != deletes, "answer \(answer)")
            #expect(run.output.contains("Nothing deleted.") != deletes)
        }
    }

    @Test("Closing input at the prompt deletes nothing")
    func promptEOF() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path("Library/Caches/org.swift.swiftpm"))
        let run = await devclean("--run", home: home, tools: tools, input: [])
        #expect(run.status == 0)
        #expect(run.standardOutput.hasSuffix("Delete 4 KB? [y/N] Nothing deleted.\n"))
        #expect(home.exists(home.path("Library/Caches/org.swift.swiftpm")))
    }

    @Test("--run with nothing found says so without asking")
    func runNothing() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        let run = await devclean("--run", home: home, tools: tools, input: nil)
        #expect(run.status == 0)
        #expect(run.standardOutput.hasSuffix("\nNothing to clean.\n"))
        #expect(!run.output.contains("Also worth a look"))
    }

    @Test("Simulator running blocks --run too, unless the Xcode items are skipped")
    func simulatorRunning() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.running = [.simulator]
        home.fill(home.path("Library/Caches/org.swift.swiftpm"))
        let blocked = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(blocked.status == 1)
        #expect(blocked.standardError == "devclean: Quit Simulator first, then run devclean --run again.\n")

        let allowed = await devclean("--run", "--yes", "--skip", "derived-data,simulators,device-installs,device-support",
                                     home: home, tools: tools)
        #expect(allowed.status == 0)
        #expect(!home.exists(home.path("Library/Caches/org.swift.swiftpm")))
    }

    @Test("Report mode never asks about running apps")
    func reportIgnoresRunningApps() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.running = [.xcode]
        let run = await devclean(home: home, tools: tools)
        #expect(run.status == 0)
        #expect(!tools.log.calls.contains { $0.hasPrefix("pgrep") })
    }

    @Test("Refuses to run as root or without a usable HOME")
    func preflight() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        let root = await devclean(home: home, tools: tools, effectiveUserID: 0)
        #expect(root.status == 1)
        #expect(root.standardError == "devclean: Don't run devclean with sudo. Everything it cleans belongs to your user.\n")
        let noHome = await devclean(home: home, tools: tools, environment: ["HOME": home.path("missing")])
        #expect(noHome.status == 1)
        #expect(noHome.standardError == "devclean: HOME must be your home folder.\n")
        #expect(noHome.standardOutput.isEmpty)
    }

    @Test("Dim text only on a terminal, and never with NO_COLOR")
    func color() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        let terminal = BufferTerminal(outputIsInteractive: true)
        _ = await CommandLineSession.run(CommandLineOptions(), environment: home.environment, tools: tools.tools, terminal: terminal)
        #expect(terminal.standardOutput.contains("\u{1B}[2m~/Library/Developer/Xcode/DerivedData\u{1B}[0m"))

        let plain = BufferTerminal(outputIsInteractive: true)
        var environment = home.environment
        environment["NO_COLOR"] = "1"
        _ = await CommandLineSession.run(CommandLineOptions(), environment: environment, tools: tools.tools, terminal: plain)
        #expect(!plain.standardOutput.contains("\u{1B}"))
    }

    @Test("Deleting prints each item, then the free space before and after")
    func deletingOutput() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path("Library/Caches/org.swift.swiftpm"))
        home.fill(home.path("Library/Caches/CocoaPods"))
        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.standardOutput.containsInOrder(
            "  Deleting SwiftPM package cache...\n", "  Deleting Tool caches (1)...\n", "\nDone. Free space: ", " -> "
        ))
        #expect(!run.output.contains("Deleting Homebrew"))
    }
}
