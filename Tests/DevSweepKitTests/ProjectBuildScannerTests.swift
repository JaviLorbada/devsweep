import Foundation
import Testing
@testable import DevSweepKit

/// Other languages' build folders, as devsweep finds them: each next to its
/// project's file, only the outermost, never one git tracks. Run as devclean,
/// the tool doesn't know them, as the bash script doesn't.
@Suite("Other languages' build folders")
struct ProjectBuildScannerTests {
    /// Each item, its folder, and the file that has to sit next to it.
    static let kinds: [(item: Item, folder: String, file: String)] = [
        (.cocoapodsPods, "Pods", "Podfile.lock"),
        (.cargoBuilds, "target", "Cargo.toml"),
        (.nodeModules, "node_modules", "package.json"),
    ]

    @Test(arguments: kinds)
    func `a folder is found next to its project's file, and ignored without one`(
        _ kind: (item: Item, folder: String, file: String)) async throws
    {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.touch("\(p)/App/\(kind.file)")
        home.fill("\(p)/App/\(kind.folder)")
        home.fill("\(p)/Loose/\(kind.folder)")
        home.mkdir("\(p)/Odd/\(kind.file)")
        home.fill("\(p)/Odd/\(kind.folder)")

        let engine = try engine(home, tools)
        let result = try #require(await collect(engine).result(kind.item))
        #expect(result.paths == ["\(engine.policy.homeReal)/Workspace/App/\(kind.folder)"])
        #expect(result.label == "\(kind.item.name) (1)")
        #expect(result.kilobytes > 0)
    }

    @Test(arguments: kinds)
    func `a folder inside another language's folder belongs to it, and isn't listed`(
        _ kind: (item: Item, folder: String, file: String)) async throws
    {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.touch("\(p)/App/\(kind.file)")
        home.fill("\(p)/App/\(kind.folder)")
        home.touch("\(p)/App/\(kind.folder)/dependency/\(kind.file)")
        home.fill("\(p)/App/\(kind.folder)/dependency/\(kind.folder)")
        for outer in ["node_modules", ".venv", "target", "Pods"] {
            home.touch("\(p)/Tool/\(outer)/lib/dependency/\(kind.file)")
            home.fill("\(p)/Tool/\(outer)/lib/dependency/\(kind.folder)")
        }

        let engine = try engine(home, tools)
        let result = try #require(await collect(engine).result(kind.item))
        #expect(result.paths == ["\(engine.policy.homeReal)/Workspace/App/\(kind.folder)"])
    }

    @Test(arguments: kinds)
    func `a folder git tracks is left alone`(_ kind: (item: Item, folder: String, file: String)) async throws {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.touch("\(p)/Tracked/\(kind.file)")
        home.fill("\(p)/Tracked/\(kind.folder)")
        home.git(["-C", "\(p)/Tracked", "init", "-q"])
        home.git(["-C", "\(p)/Tracked", "add", "-f", "\(kind.folder)/file"])
        home.touch("\(p)/Ignored/\(kind.file)")
        home.fill("\(p)/Ignored/\(kind.folder)")
        home.git(["-C", "\(p)/Ignored", "init", "-q"])

        let engine = try engine(home, tools)
        let result = try #require(await collect(engine).result(kind.item))
        #expect(result.paths == ["\(engine.policy.homeReal)/Workspace/Ignored/\(kind.folder)"])
    }

    @Test(arguments: kinds)
    func `a symlinked folder is never followed`(_ kind: (item: Item, folder: String, file: String)) async throws {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.fill(home.outside("outside"))
        home.touch("\(p)/Linked/\(kind.file)")
        home.symlink(home.outside("outside"), at: "\(p)/Linked/\(kind.folder)")

        let result = try #require(await collect(engine(home, tools)).result(kind.item))
        #expect(result.paths.isEmpty)
        #expect(home.isFile(home.outside("outside/file")))
    }

    @Test
    func `devsweep's report lists them, and its help names them`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        for kind in Self.kinds {
            home.touch("\(p)/App/\(kind.file)")
            home.fill("\(p)/App/\(kind.folder)")
        }
        let terminal = BufferTerminal()
        let status = await CommandLineSession.run(
            CommandLineOptions(),
            environment: home.environment,
            tools: tools.tools,
            terminal: terminal,
            command: .product)

        #expect(status == 0)
        #expect(terminal.output.containsInOrder(
            "  gradle-builds    Gradle build folders",
            "  cocoapods-pods   CocoaPods Pods folders (1)",
            "                   Pods next to a Podfile.lock, in project folders\n",
            "  cargo-builds     Cargo target folders (1)",
            "                   target next to a Cargo.toml, in project folders\n",
            "  node-modules     node_modules folders (1)",
            "                   node_modules next to a package.json, in project folders\n",
            "  npm-cache        npm cache"))
        #expect(CommandLineOptions.usage().contains(
            "  gradle-builds    build folders next to a Gradle build file\n"
                + "  cocoapods-pods   Pods folders next to a Podfile.lock\n"
                + "  cargo-builds     target folders next to a Cargo.toml\n"
                + "  node-modules     node_modules folders next to a package.json\n"
                + "  npm-cache        npm's download cache\n"))
        #expect(try ScanConfig.parseSkip("node-modules,cargo-builds,cocoapods-pods")
            == [.nodeModules, .cargoBuilds, .cocoapodsPods])
    }

    @Test
    func `devclean doesn't know them: its report, --skip and help stay the script's`() async {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        for kind in Self.kinds {
            home.touch("\(p)/App/\(kind.file)")
            home.fill("\(p)/App/\(kind.folder)")
        }
        // The script's search looks inside .venv and target folders.
        home.touch("\(p)/Tool/target/Swift/Package.swift")
        home.fill("\(p)/Tool/target/Swift/.build")
        home.touch("\(p)/Tool/.venv/Swift/Package.swift")
        home.fill("\(p)/Tool/.venv/Swift/.build")

        let run = await devclean(home: home, tools: tools)
        #expect(run.status == 0)
        for kind in Self.kinds {
            #expect(!run.output.contains(kind.item.rawValue))
        }
        #expect(run.output.contains("SwiftPM .build folders (2)"))

        let skip = await devclean("--skip", "node-modules", home: home, tools: tools)
        #expect(skip.status == 1)
        #expect(skip.standardError == "devclean: Unknown item 'node-modules'. Items: derived-data simulators "
            + "device-installs device-support swiftpm-cache swiftpm-builds xcode-builds gradle-builds npm-cache "
            + "homebrew tool-caches\n")
        for kind in Self.kinds {
            #expect(!CommandLineOptions.usage(.original).contains(kind.item.rawValue))
        }
    }
}
