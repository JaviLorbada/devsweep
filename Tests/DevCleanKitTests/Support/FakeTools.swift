import Foundation
import Synchronization
@testable import DevCleanKit

/// Every call a fake tool receives, like the bats suite's stub log.
final class CallLog: Sendable {
    private let entries = Mutex<[String]>([])

    func record(_ call: String) {
        self.entries.withLock { $0.append(call) }
    }

    var calls: [String] {
        self.entries.withLock { $0 }
    }

    func contains(_ call: String) -> Bool { self.calls.contains(call) }
}

/// Fake tools for one test. Nothing here runs simctl, brew, pgrep, defaults
/// or xcode-select. Git is the real one, run against the fake home, the way
/// the bats suite runs it.
final class FakeTools: @unchecked Sendable {
    let log = CallLog()
    var simctlInstalled = true
    var unavailableListing = ""
    var runtimesJSON: Data?
    var devicesJSON: Data?
    var simctlDeleteSucceeds = true
    /// Runs when `simctl delete unavailable` is called.
    var onDeleteUnavailable: @Sendable () -> Void = {}
    var brewInstalled = true
    var brewDryRun = ""
    var brewCleanupSucceeds = true
    var customDerivedData = ""
    var selectedDeveloperDirectory = ""
    var running: Set<DeveloperApp> = []
    var lastUsed: [String: Date] = [:]
    var gitEnvironment: [String: String]
    /// Replaces git with an answer, nil meaning git failed.
    var gitAnswer: (@Sendable (String, String) -> String?)?
    let trashFolder: String

    init(home: FakeHome) {
        self.gitEnvironment = home.environment
        self.trashFolder = home.path(".Trash")
    }

    var tools: Tools {
        let gitClient: any GitClient = self.gitAnswer.map { FakeGit(log: self.log, answer: $0) }
            ?? LoggingGit(
                log: self.log,
                live: LiveGitClient(runner: LiveProcessRunner(environment: self.gitEnvironment)))
        return Tools(
            simctl: FakeSimctl(
                log: self.log, installed: self.simctlInstalled, listing: self.unavailableListing,
                runtimes: self.runtimesJSON,
                devices: self.devicesJSON, deleteSucceeds: self.simctlDeleteSucceeds,
                onDelete: self.onDeleteUnavailable),
            brew: FakeBrew(
                log: self.log,
                installed: self.brewInstalled,
                dryRun: self.brewDryRun,
                cleanupSucceeds: self.brewCleanupSucceeds),
            xcodeDefaults: FakeDefaults(log: self.log, value: self.customDerivedData),
            xcodeSelect: FakeXcodeSelect(log: self.log, value: self.selectedDeveloperDirectory),
            git: gitClient,
            runningApps: FakeRunningApps(log: self.log, running: self.running),
            lastUsedDates: FakeLastUsed(dates: self.lastUsed),
            trash: LoggingTrash(trash: FolderTrash(folder: self.trashFolder), log: self.log))
    }

    /// Makes simctl report two runtimes: iOS 27.0 used today with two
    /// simulators, and iOS 17.5 last used in 2020 with none.
    func stubRuntimes(now: Date = Date()) {
        let today = ISO8601DateFormatter().string(from: now)
        self.runtimesJSON = Data(fixture("simctl-runtimes.json").replacingOccurrences(of: "$TODAY", with: today).utf8)
        self.devicesJSON = Data(fixture("simctl-devices.json").utf8)
    }
}

struct FakeSimctl: SimctlClient {
    let log: CallLog
    let installed: Bool
    let listing: String
    let runtimes: Data?
    let devices: Data?
    let deleteSucceeds: Bool
    let onDelete: @Sendable () -> Void

    var isAvailable: Bool {
        self.installed
    }

    func unavailableDevicesListing() async -> String {
        self.log.record("xcrun simctl list devices unavailable")
        return self.listing
    }

    func runtimesJSON() async -> Data? {
        self.log.record("xcrun simctl runtime list -j")
        return self.runtimes
    }

    func devicesJSON() async -> Data? {
        self.log.record("xcrun simctl list devices -j")
        return self.devices
    }

    func deleteUnavailable() async -> Bool {
        self.log.record("xcrun simctl delete unavailable")
        self.onDelete()
        return self.deleteSucceeds
    }

    func deleteRuntime(_ id: String) async -> Bool {
        self.log.record("xcrun simctl runtime delete \(id)")
        return self.deleteSucceeds
    }
}

struct FakeBrew: BrewClient {
    let log: CallLog
    let installed: Bool
    let dryRun: String
    let cleanupSucceeds: Bool

    var isAvailable: Bool {
        self.installed
    }

    func cleanupDryRun() async -> String {
        self.log.record("brew cleanup --prune=all --dry-run")
        return self.dryRun
    }

    func cleanup() async -> Bool {
        self.log.record("brew cleanup --prune=all")
        return self.cleanupSucceeds
    }
}

struct FakeDefaults: XcodeDefaultsReading {
    let log: CallLog
    let value: String

    func customDerivedDataLocation() async -> String {
        self.log.record("defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation")
        return self.value
    }
}

struct FakeXcodeSelect: XcodeSelectReading {
    let log: CallLog
    let value: String

    func selectedDeveloperDirectory() async -> String {
        self.log.record("xcode-select -p")
        return self.value
    }
}

struct FakeRunningApps: RunningAppsChecking {
    let log: CallLog
    let running: Set<DeveloperApp>

    func isRunning(_ app: DeveloperApp) async -> Bool {
        self.log.record("pgrep -xq \(app.rawValue)")
        return self.running.contains(app)
    }
}

struct FakeLastUsed: LastUsedDateReading {
    let dates: [String: Date]

    func lastUsedDate(of path: String) -> Date? { self.dates[path] }
}

struct LoggingGit: GitClient {
    let log: CallLog
    let live: LiveGitClient

    func trackedFiles(in directory: String, named name: String) async -> String? {
        self.log.record("git -C \(directory) ls-files -- \(name)")
        return await self.live.trackedFiles(in: directory, named: name)
    }
}

struct FakeGit: GitClient {
    let log: CallLog
    let answer: @Sendable (String, String) -> String?

    func trackedFiles(in directory: String, named name: String) async -> String? {
        self.log.record("git -C \(directory) ls-files -- \(name)")
        return self.answer(directory, name)
    }
}

/// A Trash inside the fake home, so tests never touch the real one.
struct LoggingTrash: TrashService {
    let trash: FolderTrash
    let log: CallLog

    func trash(_ path: String) throws -> String {
        let destination = try trash.trash(path)
        self.log.record("trash \(path)")
        return destination
    }

    func putBack(_ trashed: String, to original: String) throws {
        try self.trash.putBack(trashed, to: original)
        self.log.record("put back \(original)")
    }
}

/// Captures what a command line session writes, with standard output and
/// error kept apart and also merged in order like bats `run` sees them.
final class BufferTerminal: Terminal, @unchecked Sendable {
    private let state = Mutex<(out: String, err: String, merged: String, input: [String])>(("", "", "", []))
    let inputIsInteractive: Bool
    let outputIsInteractive: Bool

    init(input: [String]? = nil, outputIsInteractive: Bool = false) {
        self.inputIsInteractive = input != nil
        self.outputIsInteractive = outputIsInteractive
        self.state.withLock { $0.input = input ?? [] }
    }

    func write(_ text: String) {
        self.state.withLock { $0.out += text; $0.merged += text }
    }

    func warn(_ message: String) {
        self.state.withLock { $0.err += "devclean: \(message)\n"; $0.merged += "devclean: \(message)\n" }
    }

    func readLine() -> String? {
        self.state.withLock { $0.input.isEmpty ? nil : $0.input.removeFirst() }
    }

    var standardOutput: String {
        self.state.withLock { $0.out }
    }

    var standardError: String {
        self.state.withLock { $0.err }
    }

    /// Both streams in the order written, as bats `run` captures them.
    var output: String {
        self.state.withLock { $0.merged }
    }
}

/// What one command line session did.
struct SessionResult {
    let status: Int32
    let terminal: BufferTerminal

    var output: String {
        self.terminal.output
    }

    var standardOutput: String {
        self.terminal.standardOutput
    }

    var standardError: String {
        self.terminal.standardError
    }

    var lines: [String] {
        self.output.components(separatedBy: "\n")
    }
}

/// Runs devclean's command line session against the fake home: the Swift
/// equivalent of the bats suite's `run "$DEVCLEAN" ...`.
func devclean(
    _ arguments: String...,
    home: FakeHome,
    tools: FakeTools,
    environment overrides: [String: String?] = [:],
    input: [String]? = nil,
    effectiveUserID: uid_t = geteuid()) async -> SessionResult
{
    var environment = home.environment
    for (key, value) in overrides {
        environment[key] = value
    }
    let terminal = BufferTerminal(input: input)
    switch CommandLineOptions.check(arguments) {
    case .help:
        terminal.write(CommandLineOptions.usage)
        return SessionResult(status: 0, terminal: terminal)
    case let .failure(message):
        terminal.warn(message)
        return SessionResult(status: 1, terminal: terminal)
    case let .options(options):
        let status = await CommandLineSession.run(
            options,
            environment: environment,
            tools: tools.tools,
            terminal: terminal,
            effectiveUserID: effectiveUserID)
        return SessionResult(status: status, terminal: terminal)
    }
}

extension String {
    /// Like the bats glob `*"a"*"b"*`: each part appears after the previous one.
    func containsInOrder(_ parts: String...) -> Bool {
        var rest = self[...]
        for part in parts {
            guard let range = rest.range(of: part) else { return false }
            rest = rest[range.upperBound...]
        }
        return true
    }
}

/// A file from the test target's Fixtures folder, a package resource.
func fixture(_ name: String) -> String {
    let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    return try! String(contentsOf: url, encoding: .utf8)
}
