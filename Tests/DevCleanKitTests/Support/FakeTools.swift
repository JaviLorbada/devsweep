import Foundation
import Synchronization
@testable import DevCleanKit

/// Every call a fake tool receives, like the bats suite's stub log.
final class CallLog: Sendable {
    private let entries = Mutex<[String]>([])

    func record(_ call: String) {
        entries.withLock { $0.append(call) }
    }

    var calls: [String] { entries.withLock { $0 } }

    func contains(_ call: String) -> Bool { calls.contains(call) }
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
        gitEnvironment = home.environment
        trashFolder = home.path(".Trash")
    }

    var tools: Tools {
        let gitClient: any GitClient = gitAnswer.map { FakeGit(log: log, answer: $0) }
            ?? LoggingGit(log: log, live: LiveGitClient(runner: LiveProcessRunner(environment: gitEnvironment)))
        return Tools(
            simctl: FakeSimctl(
                log: log, installed: simctlInstalled, listing: unavailableListing, runtimes: runtimesJSON,
                devices: devicesJSON, deleteSucceeds: simctlDeleteSucceeds, onDelete: onDeleteUnavailable
            ),
            brew: FakeBrew(log: log, installed: brewInstalled, dryRun: brewDryRun, cleanupSucceeds: brewCleanupSucceeds),
            xcodeDefaults: FakeDefaults(log: log, value: customDerivedData),
            xcodeSelect: FakeXcodeSelect(log: log, value: selectedDeveloperDirectory),
            git: gitClient,
            runningApps: FakeRunningApps(log: log, running: running),
            lastUsedDates: FakeLastUsed(dates: lastUsed),
            trash: LoggingTrash(trash: FolderTrash(folder: trashFolder), log: log)
        )
    }

    /// Makes simctl report two runtimes: iOS 27.0 used today with two
    /// simulators, and iOS 17.5 last used in 2020 with none.
    func stubRuntimes(now: Date = Date()) {
        let today = ISO8601DateFormatter().string(from: now)
        runtimesJSON = Data("""
            {
              "RECENT-RUNTIME": {
                "build": "24A434", "version": "27.0", "sizeBytes": 8589934592,
                "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                "lastUsedAt": "\(today)"
              },
              "OLD-RUNTIME": {
                "build": "21F79", "version": "17.5", "sizeBytes": 7516192768,
                "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-17-5",
                "lastUsedAt": "2020-01-01T00:00:00Z"
              }
            }
            """.utf8)
        devicesJSON = Data("""
            { "devices": { "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [ { "name": "iPhone" }, { "name": "iPad" } ] } }
            """.utf8)
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

    var isAvailable: Bool { installed }

    func unavailableDevicesListing() async -> String {
        log.record("xcrun simctl list devices unavailable")
        return listing
    }

    func runtimesJSON() async -> Data? {
        log.record("xcrun simctl runtime list -j")
        return runtimes
    }

    func devicesJSON() async -> Data? {
        log.record("xcrun simctl list devices -j")
        return devices
    }

    func deleteUnavailable() async -> Bool {
        log.record("xcrun simctl delete unavailable")
        onDelete()
        return deleteSucceeds
    }

    func deleteRuntime(_ id: String) async -> Bool {
        log.record("xcrun simctl runtime delete \(id)")
        return deleteSucceeds
    }
}

struct FakeBrew: BrewClient {
    let log: CallLog
    let installed: Bool
    let dryRun: String
    let cleanupSucceeds: Bool

    var isAvailable: Bool { installed }

    func cleanupDryRun() async -> String {
        log.record("brew cleanup --prune=all --dry-run")
        return dryRun
    }

    func cleanup() async -> Bool {
        log.record("brew cleanup --prune=all")
        return cleanupSucceeds
    }
}

struct FakeDefaults: XcodeDefaultsReading {
    let log: CallLog
    let value: String

    func customDerivedDataLocation() async -> String {
        log.record("defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation")
        return value
    }
}

struct FakeXcodeSelect: XcodeSelectReading {
    let log: CallLog
    let value: String

    func selectedDeveloperDirectory() async -> String {
        log.record("xcode-select -p")
        return value
    }
}

struct FakeRunningApps: RunningAppsChecking {
    let log: CallLog
    let running: Set<DeveloperApp>

    func isRunning(_ app: DeveloperApp) async -> Bool {
        log.record("pgrep -xq \(app.rawValue)")
        return running.contains(app)
    }
}

struct FakeLastUsed: LastUsedDateReading {
    let dates: [String: Date]

    func lastUsedDate(of path: String) -> Date? { dates[path] }
}

struct LoggingGit: GitClient {
    let log: CallLog
    let live: LiveGitClient

    func trackedFiles(in directory: String, named name: String) async -> String? {
        log.record("git -C \(directory) ls-files -- \(name)")
        return await live.trackedFiles(in: directory, named: name)
    }
}

struct FakeGit: GitClient {
    let log: CallLog
    let answer: @Sendable (String, String) -> String?

    func trackedFiles(in directory: String, named name: String) async -> String? {
        log.record("git -C \(directory) ls-files -- \(name)")
        return answer(directory, name)
    }
}

/// A Trash inside the fake home, so tests never touch the real one.
struct LoggingTrash: TrashService {
    let trash: FolderTrash
    let log: CallLog

    func trash(_ path: String) throws -> String {
        let destination = try trash.trash(path)
        log.record("trash \(path)")
        return destination
    }

    func putBack(_ trashed: String, to original: String) throws {
        try trash.putBack(trashed, to: original)
        log.record("put back \(original)")
    }
}

/// Captures what a command line session writes, with standard output and
/// error kept apart and also merged in order like bats `run` sees them.
final class BufferTerminal: Terminal, @unchecked Sendable {
    private let state = Mutex<(out: String, err: String, merged: String, input: [String])>(("", "", "", []))
    let inputIsInteractive: Bool
    let outputIsInteractive: Bool

    init(input: [String]? = nil, outputIsInteractive: Bool = false) {
        inputIsInteractive = input != nil
        self.outputIsInteractive = outputIsInteractive
        state.withLock { $0.input = input ?? [] }
    }

    func write(_ text: String) {
        state.withLock { $0.out += text; $0.merged += text }
    }

    func warn(_ message: String) {
        state.withLock { $0.err += "devclean: \(message)\n"; $0.merged += "devclean: \(message)\n" }
    }

    func readLine() -> String? {
        state.withLock { $0.input.isEmpty ? nil : $0.input.removeFirst() }
    }

    var standardOutput: String { state.withLock { $0.out } }
    var standardError: String { state.withLock { $0.err } }
    /// Both streams in the order written, as bats `run` captures them.
    var output: String { state.withLock { $0.merged } }
}

/// What one command line session did.
struct SessionResult {
    let status: Int32
    let terminal: BufferTerminal

    var output: String { terminal.output }
    var standardOutput: String { terminal.standardOutput }
    var standardError: String { terminal.standardError }
    var lines: [String] { output.components(separatedBy: "\n") }
}

/// Runs devclean's command line session against the fake home: the Swift
/// equivalent of the bats suite's `run "$DEVCLEAN" ...`.
func devclean(
    _ arguments: String...,
    home: FakeHome,
    tools: FakeTools,
    environment overrides: [String: String?] = [:],
    input: [String]? = nil,
    effectiveUserID: uid_t = geteuid()
) async -> SessionResult {
    var environment = home.environment
    for (key, value) in overrides {
        environment[key] = value
    }
    let terminal = BufferTerminal(input: input)
    switch CommandLineOptions.check(arguments) {
    case .help:
        terminal.write(CommandLineOptions.usage)
        return SessionResult(status: 0, terminal: terminal)
    case .failure(let message):
        terminal.warn(message)
        return SessionResult(status: 1, terminal: terminal)
    case .options(let options):
        let status = await CommandLineSession.run(
            options,
            environment: environment,
            tools: tools.tools,
            terminal: terminal,
            effectiveUserID: effectiveUserID
        )
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
