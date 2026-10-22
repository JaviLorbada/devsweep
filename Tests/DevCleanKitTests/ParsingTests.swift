import Foundation
import Testing
@testable import DevCleanKit

@Suite("Command line options")
struct CommandLineOptionTests {
    @Test
    func `arguments are read left to right, like the script's parse_args`() {
        #expect(CommandLineOptions.check(["--help", "--nope"]) == .help)
        #expect(CommandLineOptions
            .check(["--nope", "--help"]) == .failure("Unknown option: --nope (see devclean --help)"))
        #expect(CommandLineOptions.check(["-h"]) == .help)
        #expect(CommandLineOptions.check(["--skip"]) == .failure("Missing value for --skip"))
        #expect(CommandLineOptions.check(["--projects"]) == .failure("Missing value for --projects"))
        #expect(CommandLineOptions.check(["--run", "extra"]) == .failure("Unknown option: extra (see devclean --help)"))
        #expect(CommandLineOptions
            .check(["--skip=homebrew"]) == .failure("Unknown option: --skip=homebrew (see devclean --help)"))
        #expect(CommandLineOptions.check(["-yh"]) == .failure("Unknown option: -yh (see devclean --help)"))
        #expect(CommandLineOptions.check(["--"]) == .failure("Unknown option: -- (see devclean --help)"))
    }

    @Test
    func `--skip and --projects take the next argument whatever it is`() {
        #expect(CommandLineOptions.check(["--skip", "--run"]) == .options(CommandLineOptions(skip: "--run")))
        #expect(CommandLineOptions.check(["--projects", "-x", "--skip", "a", "--skip", "b", "-y", "--run", "--run"])
            == .options(CommandLineOptions(run: true, yes: true, skip: "b", projects: "-x")))
        #expect(CommandLineOptions(run: true, yes: true, skip: "b", projects: "-x").arguments
            == ["--run", "--yes", "--skip", "b", "--projects", "-x"])
    }

    @Test
    func `--skip ignores whitespace and rejects the first unknown item`() throws {
        #expect(try ScanConfig.parseSkip(" derived-data,\tswiftpm-cache ,\n") == [.derivedData, .swiftpmCache])
        #expect(try ScanConfig.parseSkip("") == [])
        #expect(throws: PreflightError.unknownItem("nope")) { try ScanConfig.parseSkip("homebrew,nope,other") }
        #expect(PreflightError.unknownItem("x").description
            ==
            "Unknown item 'x'. Items: derived-data simulators device-installs device-support swiftpm-cache "
            + "swiftpm-builds xcode-builds gradle-builds npm-cache homebrew tool-caches")
    }

    @Test
    func `lists split on colons and newlines and drop empty entries`() {
        #expect(ScanConfig.splitList("a::b:\nc:") == ["a", "b", "c"])
        #expect(ScanConfig.splitList("") == [])
    }

    @Test
    func `defaults come from HOME, and empty variables count as unset`() {
        let config = ScanConfig.fromEnvironment([
            "HOME": "/h",
            "DEVCLEAN_PROJECT_DIRS": "",
            "DEVCLEAN_APPLICATIONS_DIRS": "",
        ])
        #expect(config.projectDirectories == [
            "/h/Developer",
            "/h/Development",
            "/h/dev",
            "/h/Documents/Workspace",
            "/h/Projects",
        ])
        #expect(config.applicationsDirectories == ["/Applications", "/h/Applications"])
        #expect(ScanConfig.fromEnvironment(["HOME": "/h", "DEVCLEAN_PROJECT_DIRS": "/x"], projects: "/y:/z")
            .projectDirectories == [
                "/y",
                "/z",
            ])
        #expect(ScanConfig.fromEnvironment(["HOME": "/h"], projects: "").projectDirectories == [])
    }

    @Test
    func `the four Xcode items are the ones that need Xcode closed`() {
        var config = ScanConfig(home: "/h", projectDirectories: [], applicationsDirectories: [])
        config.skipped = [.derivedData, .simulators, .deviceInstalls]
        #expect(!config.skipsEverythingXcodeUses)
        config.skipped.insert(.deviceSupport)
        #expect(config.skipsEverythingXcodeUses)
    }
}

@Suite("Tool output parsing")
struct ToolOutputParsingTests {
    @Test(arguments: [
        ("==> This operation would free approximately 1.5GB of disk space.", Int64(1_572_864)),
        ("==> This operation would free approximately 2048B of disk space.", 2),
        ("==> This operation would free approximately 1023B of disk space.", 0),
        ("==> This operation would free approximately 12KB of disk space.", 12),
        ("==> This operation would free approximately 300.5MB of disk space.", 307_712),
        ("==> This operation would free approximately 2TB of disk space.", 2_147_483_648),
        ("==> This operation would free approximately 1.5PB of disk space.", 0),
        ("==> This operation would free approximately .5GB of disk space.", 524_288),
        ("would free approximately", 0),
        ("Nothing to clean", 0),
        ("would free approximately 1GB\nwould free approximately 2MB", 2048),
    ])
    func `homebrew's dry run gives the size it would free`(output: String, kilobytes: Int64) {
        #expect(HomebrewScanner.kilobytes(fromDryRun: output) == kilobytes)
    }

    @Test
    func `unavailable simulators are the last UDID in parentheses on each line`() {
        let listing = """
        == Devices ==
        -- Unavailable: com.apple.CoreSimulator.SimRuntime.iOS-26-2 --
            iPad Pro (M5) (F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D) (Shutdown) (unavailable, runtime profile not found)
            Twice (11111111-1111-1111-1111-111111111111) (22222222-2222-2222-2222-222222222222) (Shutdown)
            lower (f3062b90-f7db-4dbf-a21d-9af6bc6ec06d) (Shutdown)
            bare F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D
        """
        #expect(SimulatorsScanner.deviceIDs(in: listing) == [
            "F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D",
            "22222222-2222-2222-2222-222222222222",
        ])
    }

    @Test(arguments: [
        ("/Users/me/Workspace/App/App.xcodeproj", "App/App"),
        ("/Users/me/Workspace/App/App.xcworkspace", "App/App"),
        ("/Users/me/Workspace/App/App.xcodeproj/", "App/App"),
        ("/Users/me/Workspace/Pkg", "Workspace/Pkg"),
        ("/App.xcodeproj", "//App"),
    ])
    func `project names come from the workspace path`(workspace: String, name: String) {
        #expect(DerivedDataScanner.projectName(workspace) == name)
    }

    @Test
    func `runtimes join devices, keep JSON order on ties, and sort by platform then newest version`() throws {
        let runtimes = Data("""
        {
          "B": { "version": "27.0", "build": "b", "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                 "sizeBytes": 1536, "lastUsedAt": "2026-10-20T00:00:00Z" },
          "A": { "version": "27.0", "build": "a", "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0" },
          "W": { "version": "11.0", "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.watchOS-11-0",
                 "lastUsedAt": "garbage" },
          "V": { "version": "9.10", "build": "", "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-9-10" },
          "T": { "version": "26.1", "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.tvOS-26-1" },
          "X": { "version": "9.2", "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-9-2" }
        }
        """.utf8)
        let devices = Data(#"{ "devices": { "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [ {}, {}, {} ] } }"#.utf8)
        let now = try #require(JavaScriptDate.parse("2026-10-21T12:00:00Z")
            .map { Date(timeIntervalSince1970: $0 / 1000) })
        let parsed = ExtrasScanner.parseRuntimes(runtimes, devices: devices, now: now)
        #expect(parsed.map(\.id) == ["B", "A", "V", "X", "T", "W"])
        #expect(parsed[0].kilobytes == 2)
        #expect(parsed[0].simulatorCount == 3)
        #expect(parsed[0].lastUsedDay == "2026-10-20")
        #expect(parsed[0].daysSinceUsed == 1)
        #expect(parsed[1].lastUsedDay == nil)
        #expect(parsed[2].build == "?")
        #expect(parsed[5].build == "?")
        #expect(parsed[5].lastUsedDay == "garbage")
        #expect(parsed[5].daysSinceUsed == nil)
        #expect(parsed[5].flagReason(staleDays: 90) == "No simulators")
    }

    @Test
    func `broken runtime JSON lists nothing`() {
        #expect(ExtrasScanner.parseRuntimes(Data("nope".utf8), devices: Data(), now: Date()).isEmpty)
        #expect(ExtrasScanner.parseRuntimes(Data("[]".utf8), devices: Data(), now: Date()).isEmpty)
        #expect(ExtrasScanner
            .parseRuntimes(Data(#"{"A": {"version": "1"}}"#.utf8), devices: Data("x".utf8), now: Date()).count == 1)
    }

    @Test(arguments: [
        ("com.apple.CoreSimulator.SimRuntime.iOS-27-0", "iOS"),
        ("com.apple.CoreSimulator.SimRuntime.xrOS-2-0", "xrOS"),
        ("SimRuntime.a.SimRuntime.tvOS-1", "tvOS"),
        ("", ""),
        ("plain", "plain"),
    ])
    func `platforms come from the runtime identifier`(identifier: String, platform: String) {
        #expect(ExtrasScanner.platform(of: identifier) == platform)
    }

    @Test
    func `dates parse like JavaScript's Date.parse`() {
        #expect(JavaScriptDate.parse("1970-01-01T00:00:00Z") == 0)
        #expect(JavaScriptDate.parse("1970-01-02") == 86_400_000)
        #expect(JavaScriptDate.parse("1970-01-01T00:00:01.250Z") == 1250)
        #expect(JavaScriptDate.parse("1970-01-01T01:00:00+01:00") == 0)
        #expect(JavaScriptDate.parse("yesterday") == nil)
        #expect(JavaScriptDate.parse("") == nil)
    }

    @Test
    func `JSON key order survives nesting, escapes and arrays`() {
        let json = Data(#"{ "z": { "a": 1, "b": [ "x", { "c": 2 } ] }, "y\"q": "v,w", "x": [] }"#.utf8)
        #expect(JSONKeyOrder.topLevelKeys(json) == ["z", "y\"q", "x"])
    }
}

@Suite("Device Support selection")
struct DeviceSupportSelectionTests {
    func entry(_ name: String, system: String = "iOS", modified: Int = 100) -> DeviceSupportScanner.Entry {
        .init(system: system, name: name, modified: modified, path: "/\(system)/\(name)")
    }

    @Test
    func `the newest version per OS and model stays; ties go to the newest build`() {
        let old = DeviceSupportScanner.old([
            self.entry("iPhone15,2 27.0 (24A435)", modified: 200),
            self.entry("iPhone15,2 27.0 (24A5264n)", modified: 100),
            self.entry("iPhone15,2 26.6.1 (23G80)"),
            self.entry("iPhone15,2 27.0 (24A435) arm64e", modified: 50),
            self.entry("iPhone17,1 26.4 (23E244)"),
            self.entry("26.4 (23E244)"),
            self.entry("26.3"),
            self.entry("26.3 arm64e"),
            self.entry("Some Folder"),
            self.entry("iPhone 15 Pro 17.0 (21A329)"),
            self.entry("iPhone15,2 Beta"),
            self.entry("27.0 (24A435)", system: "watchOS"),
            self.entry("26.0 ()"),
        ])
        #expect(old.sorted() == [
            "/iOS/26.3",
            "/iOS/iPhone15,2 26.6.1 (23G80)",
            "/iOS/iPhone15,2 27.0 (24A5264n)",
        ])
    }

    @Test
    func `versions compare as numbers, missing parts as zero`() {
        #expect(DeviceSupportScanner.old([self.entry("9.3 (a)"), self.entry("10.0 (b)")]) == ["/iOS/9.3 (a)"])
        #expect(DeviceSupportScanner.old([self.entry("17 (a)"), self.entry("17.0.1 (b)")]) == ["/iOS/17 (a)"])
        #expect(DeviceSupportScanner
            .old([self.entry("17.0 (a)", modified: 5), self.entry("17 (b)", modified: 5)]) == ["/iOS/17 (b)"])
    }

    @Test(arguments: [
        ("1", true),
        ("1.2.3", true),
        ("1.", false),
        (".1", false),
        ("1..2", false),
        ("a1", false),
        ("", false)
    ])
    func `version shapes`(text: String, isVersion: Bool) {
        #expect(DeviceSupportScanner.isVersion(text) == isVersion)
    }
}
