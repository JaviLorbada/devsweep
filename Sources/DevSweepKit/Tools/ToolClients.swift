import CoreServices
import Foundation

/// `xcrun simctl`, the only way DevSweep touches simulators.
public protocol SimctlClient: Sendable {
    /// Whether `xcrun` is installed.
    var isAvailable: Bool { get }
    /// `simctl list devices unavailable`, empty when it fails.
    func unavailableDevicesListing() async -> String
    /// `simctl runtime list -j`, nil when it fails.
    func runtimesJSON() async -> Data?
    /// `simctl list devices -j`, nil when it fails.
    func devicesJSON() async -> Data?
    /// `simctl delete unavailable`.
    func deleteUnavailable() async -> Bool
    /// `simctl runtime delete <id>`.
    func deleteRuntime(_ id: String) async -> Bool
}

/// `brew`, which measures and deletes its own leftovers.
public protocol BrewClient: Sendable {
    var isAvailable: Bool { get }
    /// What `brew cleanup --prune=all --dry-run` prints.
    func cleanupDryRun() async -> String
    /// `brew cleanup --prune=all`, output discarded.
    func cleanup() async -> Bool
}

/// `defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation`.
public protocol XcodeDefaultsReading: Sendable {
    /// The custom DerivedData location, empty when none is set.
    func customDerivedDataLocation() async -> String
}

/// `xcode-select -p`.
public protocol XcodeSelectReading: Sendable {
    /// The selected developer folder, empty when it can't tell.
    func selectedDeveloperDirectory() async -> String
}

/// `git`, asked whether it tracks anything in a folder, and about the
/// worktrees of a repository.
public protocol GitClient: Sendable {
    /// What `git -C directory ls-files -- name` prints, nil when git fails.
    func trackedFiles(in directory: String, named name: String) async -> String?
    /// What `git -C directory worktree list --porcelain` prints, nil when git fails.
    func worktreeList(in directory: String) async -> String?
    /// What `git -C directory status --porcelain` prints, one line per changed
    /// or untracked file; nil when git fails.
    func status(in directory: String) async -> String?
    /// The branches and remote branches that contain HEAD, one per line; nil
    /// when git fails.
    func refsContainingHead(in directory: String) async -> String?
    /// When HEAD was committed, as `git log -1 --format=%ct` prints it; nil
    /// when git fails.
    func headCommitTime(in directory: String) async -> String?
    /// `git -C repository worktree remove path`, never forced: git refuses a
    /// worktree with changes, and keeps its branch.
    func removeWorktree(_ path: String, from repository: String) async -> Bool
}

/// Whether Xcode or Simulator is running.
public protocol RunningAppsChecking: Sendable {
    func isRunning(_ app: DeveloperApp) async -> Bool
}

public enum DeveloperApp: String, Sendable, CaseIterable {
    case xcode = "Xcode"
    case simulator = "Simulator"

    public var bundleIdentifier: String {
        switch self {
        case .xcode: "com.apple.dt.Xcode"
        case .simulator: "com.apple.iphonesimulator"
        }
    }
}

/// When an app was last opened, from Spotlight.
public protocol LastUsedDateReading: Sendable {
    func lastUsedDate(of path: String) -> Date?
}

// MARK: - Live implementations

public struct LiveSimctlClient: SimctlClient {
    let runner: any ProcessRunning
    /// Lets `simctl delete` print to the terminal, as the bash script let it.
    let passthroughDeletes: Bool

    public init(runner: any ProcessRunning, passthroughDeletes: Bool = false) {
        self.runner = runner
        self.passthroughDeletes = passthroughDeletes
    }

    public var isAvailable: Bool {
        self.runner.locate("xcrun") != nil
    }

    public func unavailableDevicesListing() async -> String {
        guard let output = await runner.run("xcrun", ["simctl", "list", "devices", "unavailable"]) else { return "" }
        return String(decoding: output.standardOutput, as: UTF8.self)
    }

    public func runtimesJSON() async -> Data? {
        guard let output = await runner.run("xcrun", ["simctl", "runtime", "list", "-j"]),
              output.succeeded else { return nil }
        return output.standardOutput
    }

    public func devicesJSON() async -> Data? {
        await self.runner.run("xcrun", ["simctl", "list", "devices", "-j"])?.standardOutput
    }

    public func deleteUnavailable() async -> Bool {
        await self.runner.run("xcrun", ["simctl", "delete", "unavailable"], passthrough: self.passthroughDeletes)?
            .succeeded ?? false
    }

    public func deleteRuntime(_ id: String) async -> Bool {
        await self.runner.run("xcrun", ["simctl", "runtime", "delete", id], passthrough: self.passthroughDeletes)?
            .succeeded ?? false
    }
}

public struct LiveBrewClient: BrewClient {
    let runner: any ProcessRunning

    public init(runner: any ProcessRunning) {
        self.runner = runner
    }

    public var isAvailable: Bool {
        self.runner.locate("brew") != nil
    }

    public func cleanupDryRun() async -> String {
        guard let output = await runner.run("brew", ["cleanup", "--prune=all", "--dry-run"]) else { return "" }
        return String(decoding: output.standardOutput, as: UTF8.self)
    }

    public func cleanup() async -> Bool {
        await self.runner.run("brew", ["cleanup", "--prune=all"])?.succeeded ?? false
    }
}

public struct LiveXcodeDefaults: XcodeDefaultsReading {
    let runner: any ProcessRunning

    public init(runner: any ProcessRunning) {
        self.runner = runner
    }

    public func customDerivedDataLocation() async -> String {
        await self.runner.run("defaults", ["read", "com.apple.dt.Xcode", "IDECustomDerivedDataLocation"])?.text ?? ""
    }
}

public struct LiveXcodeSelect: XcodeSelectReading {
    let runner: any ProcessRunning

    public init(runner: any ProcessRunning) {
        self.runner = runner
    }

    public func selectedDeveloperDirectory() async -> String {
        await self.runner.run("xcode-select", ["-p"])?.text ?? ""
    }
}

public struct LiveGitClient: GitClient {
    let runner: any ProcessRunning

    public init(runner: any ProcessRunning) {
        self.runner = runner
    }

    public func trackedFiles(in directory: String, named name: String) async -> String? {
        await self.text(["-C", directory, "ls-files", "--", name])
    }

    public func worktreeList(in directory: String) async -> String? {
        await self.text(["-C", directory, "worktree", "list", "--porcelain"])
    }

    public func status(in directory: String) async -> String? {
        await self.text(["-C", directory, "status", "--porcelain"])
    }

    public func refsContainingHead(in directory: String) async -> String? {
        await self.text([
            "-C", directory, "for-each-ref", "--contains", "HEAD", "--format=%(refname)", "refs/heads", "refs/remotes",
        ])
    }

    public func headCommitTime(in directory: String) async -> String? {
        await self.text(["-C", directory, "log", "-1", "--format=%ct"])
    }

    public func removeWorktree(_ path: String, from repository: String) async -> Bool {
        await self.runner.run("git", ["-C", repository, "worktree", "remove", path])?.succeeded ?? false
    }

    private func text(_ arguments: [String]) async -> String? {
        guard let output = await runner.run("git", arguments), output.succeeded else { return nil }
        return output.text
    }
}

/// Asks `pgrep -xq`, found through `PATH`, like the bash script did.
public struct PgrepRunningApps: RunningAppsChecking {
    let runner: any ProcessRunning

    public init(runner: any ProcessRunning) {
        self.runner = runner
    }

    public func isRunning(_ app: DeveloperApp) async -> Bool {
        await self.runner.run("pgrep", ["-xq", app.rawValue])?.succeeded ?? false
    }
}

public struct SpotlightLastUsedDates: LastUsedDateReading {
    public init() {}

    public func lastUsedDate(of path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString),
              let value = MDItemCopyAttribute(item, kMDItemLastUsedDate)
        else {
            return nil
        }
        return value as? Date
    }
}
