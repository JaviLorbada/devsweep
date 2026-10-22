import Foundation
import Testing
@testable import DevCleanKit

// One test per test in the bash script's test/devclean.bats, in the same order
// and with the same names, run through the same command line session the
// binary runs, against a fake home with fake tools.

@Suite("Options")
struct OptionsTests {
    @Test
    func `devclean --help explains usage`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        let run = await devclean("--help", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("Usage: devclean"))
    }

    @Test
    func `devclean rejects unknown options`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        let run = await devclean("--nope", home: home, tools: tools)
        #expect(run.status != 0)
        #expect(run.output.contains("Unknown option: --nope"))
    }

    @Test
    func `devclean rejects unknown --skip items`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        let run = await devclean("--skip", "derived-data,nope", home: home, tools: tools)
        #expect(run.status != 0)
        #expect(run.output.contains("Unknown item 'nope'"))
    }
}

@Suite("Reporting")
struct ReportingTests {
    @Test
    func `devclean reports without deleting by default`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path("\(FakeHome.derivedData)/CompilationCache.noindex"))
        home.fill(home.path("Library/Caches/org.swift.swiftpm/repositories"))

        let run = await devclean(home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("derived-data"))
        #expect(run.output.contains("swiftpm-cache"))
        #expect(run.output.contains("Nothing deleted"))
        #expect(home.isDirectory(home.path(FakeHome.derivedData)))
        #expect(home.isDirectory(home.path("Library/Caches/org.swift.swiftpm")))
    }

    @Test
    func `devclean says so when there is nothing to clean`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        let run = await devclean(home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("Nothing to clean"))
    }

    @Test
    func `devclean lists every item and where it looks, even when empty`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        let run = await devclean(home: home, tools: tools)
        #expect(run.status == 0)
        for id in [
            "derived-data",
            "simulators",
            "device-installs",
            "swiftpm-cache",
            "swiftpm-builds",
            "xcode-builds",
            "gradle-builds",
            "npm-cache",
            "homebrew",
            "tool-caches",
        ] {
            #expect(run.output.contains(id))
        }
        #expect(run.output.contains("~/Library/Developer/Xcode/DerivedData"))
        #expect(run.output.contains("~/Library/Caches/org.swift.swiftpm"))
        #expect(run.lines.filter { $0.hasSuffix(" none") }.count >= 10)
    }

    @Test
    func `devclean shows which project folders it searches`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        let run = await devclean(
            home: home,
            tools: tools,
            environment: ["DEVCLEAN_PROJECT_DIRS": "\(home.home)/Workspace:\(home.home)/Missing"])
        #expect(run.status == 0)
        #expect(run.output.contains("Project folders: ~/Workspace (not found: ~/Missing)"))
    }

    @Test
    func `devclean says when no project folder exists`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        let run = await devclean("--projects", home.path("Nope"), home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("Project folders: none found (looked for ~/Nope)"))
        #expect(run.output.contains("--projects"))
    }

    @Test
    func `devclean skips items with --skip in the report too`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        let run = await devclean("--skip", "homebrew", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(!run.output.contains("homebrew"))
    }

    @Test
    func `devclean expands ~ in DEVCLEAN_PROJECT_DIRS`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.touch("\(home.projects)/Package.swift")
        home.fill("\(home.projects)/.build")

        let run = await devclean(home: home, tools: tools, environment: ["DEVCLEAN_PROJECT_DIRS": "~/Workspace"])
        #expect(run.status == 0)
        #expect(run.output.contains("swiftpm-builds"))
        #expect(run.output.contains("SwiftPM .build folders (1)"))
    }

    @Test
    func `devclean --projects overrides the project folders`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.touch(home.path("Code/Package.swift"))
        home.fill(home.path("Code/.build"))

        let run = await devclean("--projects", home.path("Code"), home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("SwiftPM .build folders (1)"))
    }
}

@Suite("Deleting")
struct DeletingTests {
    @Test
    func `devclean --run --yes deletes caches`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path("\(FakeHome.derivedData)/CompilationCache.noindex"))
        home.fill(home.path(FakeHome.deviceInstalls))
        home.fill(home.path("Library/Caches/org.swift.swiftpm"))
        home.fill(home.path(".npm/_cacache"))
        home.fill(home.path("Library/Caches/CocoaPods"))

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("Done. Free space:"))
        #expect(!home.exists(home.path(FakeHome.derivedData)))
        #expect(!home.exists(home.path(FakeHome.deviceInstalls)))
        #expect(!home.exists(home.path("Library/Caches/org.swift.swiftpm")))
        #expect(!home.exists(home.path(".npm/_cacache")))
        #expect(!home.exists(home.path("Library/Caches/CocoaPods")))
        #expect(home.isDirectory(home.path(".npm")))
    }

    @Test
    func `devclean --run refuses to delete without a terminal or --yes`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path(FakeHome.derivedData))

        let run = await devclean("--run", home: home, tools: tools, input: nil)
        #expect(run.status != 0)
        #expect(run.output.contains("--yes"))
        #expect(home.isDirectory(home.path(FakeHome.derivedData)))
    }

    @Test
    func `devclean --run refuses while Xcode is running`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.running = [.xcode]
        home.fill(home.path(FakeHome.derivedData))

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status != 0)
        #expect(run.output.contains("Quit Xcode"))
        #expect(home.isDirectory(home.path(FakeHome.derivedData)))
    }

    @Test
    func `devclean --skip leaves items alone`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path(FakeHome.derivedData))
        home.fill(home.path("Library/Caches/org.swift.swiftpm"))

        let run = await devclean("--run", "--yes", "--skip", "derived-data", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(home.isDirectory(home.path(FakeHome.derivedData)))
        #expect(!home.exists(home.path("Library/Caches/org.swift.swiftpm")))
    }
}

@Suite("Build folders")
struct BuildFolderTests {
    @Test
    func `devclean only deletes .build folders next to a Package.swift`() async {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.touch("\(p)/App/Packages/Core/Package.swift")
        home.fill("\(p)/App/Packages/Core/.build")
        home.fill("\(p)/Other/.build")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(!home.exists("\(p)/App/Packages/Core/.build"))
        #expect(home.isDirectory("\(p)/Other/.build"))
    }

    @Test
    func `devclean only deletes build folders next to a Gradle file`() async {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.touch("\(p)/android/app/build.gradle.kts")
        home.fill("\(p)/android/app/build")
        home.fill("\(p)/website/build")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(!home.exists("\(p)/android/app/build"))
        #expect(home.isDirectory("\(p)/website/build"))
    }

    @Test
    func `devclean deletes Xcode build folders next to a project or package`() async {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.mkdir("\(p)/App/App.xcodeproj")
        home.mkdir("\(p)/App/Packages/Domain")
        home.fillXcodeBuild("\(p)/App/build")
        home.touch("\(p)/App/Packages/Domain/Package.swift")
        home.fill("\(p)/App/Packages/Domain/build/Debug-iphoneos")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("Xcode build folders (2)"))
        #expect(!home.exists("\(p)/App/build"))
        #expect(!home.exists("\(p)/App/Packages/Domain/build"))
        #expect(home.isDirectory("\(p)/App/App.xcodeproj"))
    }

    @Test
    func `devclean keeps build folders next to a package that hold no Xcode output`() async {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.touch("\(p)/Worksheets/Package.swift")
        home.write("\(p)/Worksheets/build/worksheet.pdf", "pdf\n")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(home.isFile("\(p)/Worksheets/build/worksheet.pdf"))
    }

    @Test
    func `devclean keeps Xcode output that isn't next to a project or package`() async {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.fillXcodeBuild("\(p)/Loose/build")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(home.isDirectory("\(p)/Loose/build/XCBuildData"))
    }

    @Test
    func `devclean counts a build folder next to both Gradle and Xcode files once`() async {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.touch("\(p)/Multiplatform/build.gradle.kts")
        home.touch("\(p)/Multiplatform/Package.swift")
        home.fillXcodeBuild("\(p)/Multiplatform/build")

        let run = await devclean(home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("Gradle build folders (1)"))
        #expect(!run.output.contains("Xcode build folders (1)"))
    }

    @Test
    func `devclean keeps build folders tracked in git`() async {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.touch("\(p)/Tracked/Package.swift")
        home.fill("\(p)/Tracked/.build")
        home.git(["-C", "\(p)/Tracked", "init", "-q"])
        home.git(["-C", "\(p)/Tracked", "add", "-f", ".build/file"])

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(home.isFile("\(p)/Tracked/.build/file"))
    }

    @Test
    func `devclean handles folder names with spaces`() async {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.touch("\(p)/My App/Package.swift")
        home.fill("\(p)/My App/.build")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(!home.exists("\(p)/My App/.build"))
        #expect(home.isFile("\(p)/My App/Package.swift"))
    }

    @Test
    func `devclean does not follow symlinked build folders`() async {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.fill(home.outside("outside"))
        home.touch("\(p)/Linked/Package.swift")
        home.symlink(home.outside("outside"), at: "\(p)/Linked/.build")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(home.isFile(home.outside("outside/file")))
    }
}

@Suite("Xcode and tools")
struct XcodeAndToolsTests {
    @Test
    func `devclean uses a custom DerivedData folder inside the home folder`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path("Custom/DerivedData"))
        tools.customDerivedData = home.path("Custom/DerivedData")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(!home.exists(home.path("Custom/DerivedData")))
    }

    @Test
    func `devclean ignores a custom DerivedData folder outside the home folder`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.outside("elsewhere/DerivedData"))
        tools.customDerivedData = home.outside("elsewhere/DerivedData")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(home.isFile(home.outside("elsewhere/DerivedData/file")))
    }

    @Test
    func `devclean deletes unavailable simulators through simctl`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.unavailableListing = """
        -- Unavailable: com.apple.CoreSimulator.SimRuntime.iOS-26-2 --
            iPad Pro (M5) (F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D) (Shutdown) (unavailable, runtime profile not found)

        """
        home.fill(home.path("Library/Developer/CoreSimulator/Devices/F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D"))

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("Simulators without a runtime (1)"))
        #expect(tools.log.contains("xcrun simctl delete unavailable"))
    }

    @Test
    func `devclean reports and runs Homebrew cleanup`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.brewDryRun = "==> This operation would free approximately 1.5GB of disk space.\n"

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("1.5 GB"))
        #expect(tools.log.contains("brew cleanup --prune=all"))
    }
}

@Suite("Xcodes and simulator runtimes (listed, never deleted)")
struct ExtrasListingTests {
    @Test
    func `devclean lists installed Xcodes and marks the selected one`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.makeXcode(home.path("Applications/Xcode.app"), version: "27.0", build: "27A266a")
        home.makeXcode(home.path("Applications/Xcode-27.1.app"), version: "27.1", build: "27A9269")
        tools.selectedDeveloperDirectory = home.path("Applications/Xcode.app/Contents/Developer")

        let run = await devclean(home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("Xcode 27.0 (27A266a)"))
        #expect(run.output.contains("Xcode 27.1 (27A9269)"))
        #expect(run.lines.filter { $0.contains("selected") }.count == 1)
        #expect(run.lines.first { $0.contains("Xcode 27.0") }?.contains("selected") == true)
        #expect(run.output.contains("Each Xcode keeps its own compilation cache"))
    }

    @Test
    func `devclean only mentions the compilation cache with more than one Xcode`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.makeXcode(home.path("Applications/Xcode.app"), version: "27.0", build: "27A266a")

        let run = await devclean(home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("Xcode 27.0 (27A266a)"))
        #expect(!run.output.contains("Each Xcode keeps its own compilation cache"))
    }

    @Test
    func `devclean lists simulator runtimes and flags unused ones`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        let now = Date()
        tools.stubRuntimes(now: now)
        let today = DayFormat.utc(now)

        let run = await devclean(home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.containsInOrder("iOS 27.0 (24A434)", "8.0 GB", "used \(today), 2 simulators"))
        #expect(run.output.containsInOrder("iOS 17.5 (21F79)", "used 2020-01-01, 0 simulators"))
        #expect(run.output.contains("no simulators. Remove with: xcrun simctl runtime delete OLD-RUNTIME"))
        #expect(!run.output.contains("delete RECENT-RUNTIME"))
    }

    @Test
    func `devclean says when no runtime looks unused`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.stubRuntimes()
        tools.runtimesJSON = Data("""
        { "RECENT-RUNTIME": { "build": "24A434", "version": "27.0", "sizeBytes": 1024,
          "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
          "lastUsedAt": "\(ISO8601DateFormatter().string(from: Date()))" } }
        """.utf8)

        let run = await devclean(home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("None look unused"))
    }

    @Test
    func `devclean never deletes Xcodes or runtimes`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.makeXcode(home.path("Applications/Xcode.app"), version: "27.0", build: "27A266a")
        home.makeXcode(home.path("Applications/Xcode-27.1.app"), version: "27.1", build: "27A9269")
        tools.stubRuntimes()
        home.fill(home.path(FakeHome.derivedData))

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(home.isDirectory(home.path("Applications/Xcode.app")))
        #expect(home.isDirectory(home.path("Applications/Xcode-27.1.app")))
        #expect(!tools.log.calls.contains { $0.contains("runtime delete") })
        #expect(!run.output.contains("Xcode versions"))
    }
}

@Suite("Safety regressions")
struct SafetyRegressionTests {
    @Test
    func `devclean never deletes through a symlinked parent folder that leads outside home`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.outside("outside-caches/org.swift.swiftpm"))
        home.mkdir(home.path("Library"))
        home.symlink(home.outside("outside-caches"), at: home.path("Library/Caches"))

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(home.isFile(home.outside("outside-caches/org.swift.swiftpm/file")))
    }

    @Test
    func `devclean ignores a custom DerivedData path that climbs out of home with ..`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.outside("victim/DerivedData"))
        tools.customDerivedData = "\(home.home)/../victim/DerivedData"

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(home.isFile(home.outside("victim/DerivedData/file")))
    }

    @Test
    func `devclean leaves a DerivedData folder that is itself a symlink alone`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.outside("external/DerivedData"))
        home.mkdir(home.path("Library/Developer/Xcode"))
        home.symlink(home.outside("external/DerivedData"), at: home.path(FakeHome.derivedData))

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(home.isSymlink(home.path(FakeHome.derivedData)))
        #expect(home.isFile(home.outside("external/DerivedData/file")))
    }

    @Test
    func `devclean skips project folders that lead outside home`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.touch(home.outside("external-code/App/Package.swift"))
        home.fill(home.outside("external-code/App/.build"))
        home.symlink(home.outside("external-code"), at: home.path("Code"))

        let run = await devclean("--run", "--yes", "--projects", home.path("Code"), home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("outside your home folder, skipped: ~/Code"))
        #expect(home.isFile(home.outside("external-code/App/.build/file")))
    }

    @Test
    func `devclean checks each path again right before deleting it`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path("Library/Developer/CoreSimulator/Devices/F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D"))
        home.fill(home.path("Library/Caches/org.swift.swiftpm"))
        tools.unavailableListing =
            "    Old (F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D) (Shutdown) (unavailable, runtime profile not found)\n"
        // Deleting simulators runs before the SwiftPM cache. Use that moment to
        // swap ~/Library/Caches for a symlink to a folder outside home.
        let caches = home.path("Library/Caches"), moved = home.outside("moved-caches")
        tools.onDeleteUnavailable = {
            must { try FileManager.default.moveItem(atPath: caches, toPath: moved) }
            must { try FileManager.default.createSymbolicLink(atPath: caches, withDestinationPath: moved) }
        }

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("changed since the scan"))
        #expect(home.isFile(home.outside("moved-caches/org.swift.swiftpm/file")))
    }

    @Test
    func `devclean keeps build folders when git can't tell whether they're tracked`() async {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.touch("\(p)/Broken/Package.swift")
        home.fill("\(p)/Broken/.build")
        home.git(["-C", "\(p)/Broken", "init", "-q"])
        home.git(["-C", "\(p)/Broken", "add", "-f", ".build/file"])
        home.write("\(p)/Broken/.git/index", "corrupt\n")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("couldn't check whether git tracks it"))
        #expect(home.isFile("\(p)/Broken/.build/file"))
    }

    @Test
    func `devclean still deletes untracked build folders inside a healthy git repo`() async {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.touch("\(p)/Healthy/Package.swift")
        home.fill("\(p)/Healthy/.build")
        home.git(["-C", "\(p)/Healthy", "init", "-q"])

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(!home.exists("\(p)/Healthy/.build"))
    }

    @Test
    func `devclean asks git about build folders when GIT_DIR and GIT_WORK_TREE are set`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        let workTree = "\(home.projects)/Detached", gitDir = home.outside("metadata.git")
        home.touch("\(workTree)/Package.swift")
        home.fill("\(workTree)/.build")
        home.git(["--git-dir=\(gitDir)", "--work-tree=\(workTree)", "init", "-q"])
        home.git(["-C", workTree, "--git-dir=\(gitDir)", "--work-tree=\(workTree)", "add", "-f", ".build/file"])
        #expect(!home.exists("\(workTree)/.git"))
        tools.gitEnvironment["GIT_DIR"] = gitDir
        tools.gitEnvironment["GIT_WORK_TREE"] = workTree

        let run = await devclean(
            "--run",
            "--yes",
            home: home,
            tools: tools,
            environment: ["GIT_DIR": gitDir, "GIT_WORK_TREE": workTree])
        #expect(run.status == 0)
        // Kept because git answered "tracked", not because the query failed
        #expect(!run.output.contains("couldn't check whether git tracks it"))
        #expect(home.isFile("\(workTree)/.build/file"))
    }

    @Test
    func `devclean keeps build folders when .git is a symlink to a missing disk`() async {
        let home = FakeHome(), tools = FakeTools(home: home), p = home.projects
        home.touch("\(p)/External/Package.swift")
        home.fill("\(p)/External/.build")
        home.symlink(home.outside("unplugged-disk/External.git"), at: "\(p)/External/.git")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("couldn't check whether git tracks it"))
        #expect(home.isFile("\(p)/External/.build/file"))
    }

    @Test
    func `devclean --skip accepts spaces after the commas`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path(FakeHome.derivedData))
        home.fill(home.path("Library/Caches/org.swift.swiftpm"))

        let run = await devclean("--run", "--yes", "--skip", "derived-data, swiftpm-cache", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(home.isDirectory(home.path(FakeHome.derivedData)))
        #expect(home.isFile(home.path("Library/Caches/org.swift.swiftpm/file")))
    }
}

@Suite("Device Support")
struct DeviceSupportTests {
    @Test
    func `devclean deletes older Device Support but keeps the newest per device model`() async {
        let home = FakeHome(), tools = FakeTools(home: home), ds = home.path(FakeHome.iosDeviceSupport)
        home.makeDeviceSupport("\(ds)/iPhone15,2 27.0 (24A435)")
        home.makeDeviceSupport("\(ds)/iPhone15,2 26.6.1 (23G80)")
        home.makeDeviceSupport("\(ds)/iPhone17,1 26.4 (23E244)")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.output.contains("Old Device Support (1)"))
        #expect(!home.exists("\(ds)/iPhone15,2 26.6.1 (23G80)"))
        #expect(home.isDirectory("\(ds)/iPhone15,2 27.0 (24A435)"))
        #expect(home.isDirectory("\(ds)/iPhone17,1 26.4 (23E244)"))
    }

    @Test
    func `devclean compares Device Support versions as numbers`() async {
        let home = FakeHome(), tools = FakeTools(home: home), ds = home.path(FakeHome.iosDeviceSupport)
        home.makeDeviceSupport("\(ds)/iPhone9,1 9.3 (13E233)")
        home.makeDeviceSupport("\(ds)/iPhone9,1 10.0 (14A346)")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(!home.exists("\(ds)/iPhone9,1 9.3 (13E233)"))
        #expect(home.isDirectory("\(ds)/iPhone9,1 10.0 (14A346)"))
    }

    @Test
    func `devclean handles Device Support names without a device and arch copies`() async {
        let home = FakeHome(), tools = FakeTools(home: home), ds = home.path(FakeHome.iosDeviceSupport)
        home.makeDeviceSupport("\(ds)/16.4 (20E247) arm64e")
        home.makeDeviceSupport("\(ds)/16.4 (20E247)")
        home.makeDeviceSupport("\(ds)/15.5 (19F77)")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(!home.exists("\(ds)/15.5 (19F77)"))
        #expect(home.isDirectory("\(ds)/16.4 (20E247) arm64e"))
        #expect(home.isDirectory("\(ds)/16.4 (20E247)"))
    }

    @Test
    func `devclean keeps Device Support it can't parse and handles each OS separately`() async {
        let home = FakeHome(), tools = FakeTools(home: home), xcode = home.path("Library/Developer/Xcode")
        home.makeDeviceSupport("\(xcode)/iOS DeviceSupport/Some Folder")
        home.makeDeviceSupport("\(xcode)/iOS DeviceSupport/iPhone15,2 Beta")
        home.makeDeviceSupport("\(xcode)/watchOS DeviceSupport/Watch6,1 11.0 (22R349)")
        home.makeDeviceSupport("\(xcode)/watchOS DeviceSupport/Watch6,1 10.5 (21T576)")
        home.makeDeviceSupport("\(xcode)/macOS DeviceSupport/15.0")
        home.makeDeviceSupport("\(xcode)/macOS DeviceSupport/14.5")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(home.isDirectory("\(xcode)/iOS DeviceSupport/Some Folder"))
        #expect(home.isDirectory("\(xcode)/iOS DeviceSupport/iPhone15,2 Beta"))
        #expect(!home.exists("\(xcode)/watchOS DeviceSupport/Watch6,1 10.5 (21T576)"))
        #expect(home.isDirectory("\(xcode)/watchOS DeviceSupport/Watch6,1 11.0 (22R349)"))
        #expect(!home.exists("\(xcode)/macOS DeviceSupport/14.5"))
        #expect(home.isDirectory("\(xcode)/macOS DeviceSupport/15.0"))
    }

    @Test
    func `devclean keeps the most recently used build when a version has several`() async {
        let home = FakeHome(), tools = FakeTools(home: home), ds = home.path(FakeHome.iosDeviceSupport)
        home.makeDeviceSupport("\(ds)/iPhone15,2 27.0 (24A5264n)", modified: "202609010000")
        home.makeDeviceSupport("\(ds)/iPhone15,2 27.0 (24A435)", modified: "202609200000")

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.status == 0)
        #expect(!home.exists("\(ds)/iPhone15,2 27.0 (24A5264n)"))
        #expect(home.isDirectory("\(ds)/iPhone15,2 27.0 (24A435)"))
    }
}

@Suite("DerivedData breakdown")
struct DerivedDataBreakdownTests {
    @Test
    func `devclean breaks DerivedData down into shared caches and projects`() async {
        let home = FakeHome(), tools = FakeTools(home: home), dd = home.path(FakeHome.derivedData)
        home.fill("\(dd)/CompilationCache.noindex")
        home.fill("\(dd)/ModuleCache.noindex")
        home.fill("\(dd)/SymbolCache.noindex")
        home.mkdir("\(home.projects)/App/App.xcodeproj")
        home.makeDerivedData(
            "\(dd)/App-abcdefghijklmnopqrstuvwxyz",
            workspace: "\(home.projects)/App/App.xcodeproj",
            lastAccessed: "2026-09-30T10:00:00Z")
        home.makeDerivedData(
            "\(dd)/Old-bcdefghijklmnopqrstuvwxyza",
            workspace: "\(home.projects)/Old/Old.xcodeproj",
            lastAccessed: "2026-03-02T10:00:00Z")

        let run = await devclean(home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.lines.contains { $0.contains(#/^ {21}Compilation cache, all projects +[0-9]/#) })
        #expect(run.lines.contains { $0.contains(#/^ {21}Module cache, all projects +[0-9]/#) })
        #expect(run.lines.contains { $0.contains(#/^ {21}App/App +built 2026-09-30 +[0-9]/#) })
        #expect(run.lines.contains { $0.contains(#/^ {21}Old/Old +project gone +[0-9]/#) })
        #expect(run.lines.contains { $0.contains(#/^ {21}Other +[0-9]/#) })
        #expect(run.output.contains("Each part comes back as you build"))
        #expect(home.isDirectory("\(dd)/App-abcdefghijklmnopqrstuvwxyz"))
    }

    @Test
    func `devclean shows the five biggest DerivedData projects and sums the rest`() async {
        let home = FakeHome(), tools = FakeTools(home: home), dd = home.path(FakeHome.derivedData)
        for n in 1...7 {
            home.mkdir("\(home.projects)/P\(n)/P\(n).xcodeproj")
            home.makeDerivedData(
                "\(dd)/P\(n)-abcdefghijklmnopqrstuvwxyz",
                workspace: "\(home.projects)/P\(n)/P\(n).xcodeproj",
                lastAccessed: "2026-09-30T10:00:00Z")
        }
        home.writeZeros("\(dd)/P7-abcdefghijklmnopqrstuvwxyz/big", kilobytes: 2048)

        let run = await devclean(home: home, tools: tools)
        #expect(run.status == 0)
        #expect(run.lines.contains { $0.contains(#/^ {21}P7/P7 +built 2026-09-30 +2 MB$/#) })
        #expect(run.lines.contains { $0.contains(#/^ {21}2 more projects +[0-9]/#) })
        #expect(run.lines.filter { $0.contains(#/^ {21}P[0-9]/P[0-9] /#) }.count == 5)
    }
}

@Suite("Locale")
struct LocaleTests {
    @Test
    func `devclean reads and prints sizes the same in a comma-decimal locale`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.brewDryRun = "==> This operation would free approximately 1.5GB of disk space.\n"

        let run = await devclean(home: home, tools: tools, environment: ["LC_ALL": "es_ES.UTF-8"])
        #expect(run.status == 0)
        #expect(run.output.contains("1.5 GB"))
    }
}

@Suite("Default project folders")
struct DefaultProjectFolderTests {
    @Test
    func `devclean looks in ~/Development and ~/dev by default`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.mkdir(home.path("Development"))
        home.touch(home.path("dev/App/Package.swift"))
        home.fill(home.path("dev/App/.build"))
        // The fake home's Workspace is not one of the defaults' names.
        try? FileManager.default.removeItem(atPath: home.projects)

        let run = await devclean(home: home, tools: tools, environment: ["DEVCLEAN_PROJECT_DIRS": nil])
        #expect(run.status == 0)
        #expect(run.output.contains(
            "Project folders: ~/Development, ~/dev (not found: ~/Developer, ~/Documents/Workspace, ~/Projects)"))
        #expect(run.output.contains("SwiftPM .build folders (1)"))
    }
}
