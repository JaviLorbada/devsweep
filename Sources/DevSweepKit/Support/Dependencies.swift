import Foundation

/// Everything the kit reads from or does to the machine, in one value. The
/// app and the command line build the live one; tests build fakes, so no
/// test needs a stub on PATH. The path policy stays on the real disk on
/// purpose: it is the safety check, and faking it would test nothing.
public struct Dependencies: Sendable {
    /// simctl, brew, defaults, xcode-select, git, Spotlight's last-used
    /// dates, running apps and the Trash: everything that runs a process or
    /// asks the system.
    public var tools: Tools
    /// Listing, reading and removing files.
    public var files: any FileSystemAccess
    public var clock: any WallClock

    public init(tools: Tools, files: any FileSystemAccess = LiveFileSystem(), clock: any WallClock = SystemClock()) {
        self.tools = tools
        self.files = files
        self.clock = clock
    }

    /// The machine as it is, with tools found through the environment's `PATH`.
    public static func live(environment: [String: String], passthroughOutput: Bool = false) -> Dependencies {
        Dependencies(tools: .live(environment: environment, passthroughOutput: passthroughOutput))
    }
}

/// Listing, reading and removing files and folders.
public protocol FileSystemAccess: Sendable {
    /// Names inside a directory, without `.` and `..`, in no particular order.
    func childNames(_ directory: String) -> [String]
    func isDirectory(_ path: String) -> Bool
    func isSymlink(_ path: String) -> Bool
    func exists(_ path: String) -> Bool
    /// Modification time in seconds of the path itself, 0 when it can't be read.
    func modificationTime(_ path: String) -> Int
    func contents(of path: String) -> Data?
    /// Removes a file, or a folder and everything in it.
    func remove(_ path: String) throws
}

extension FileSystemAccess {
    /// The names a bash glob `dir/*` expands to: no hidden names, sorted the
    /// way `LC_ALL=C` sorts them.
    func globNames(_ directory: String) -> [String] {
        childNames(directory).filter { !$0.hasPrefix(".") }.sortedBytewise()
    }
}

/// The disk, through POSIX and FileManager.
public struct LiveFileSystem: FileSystemAccess {
    public init() {}

    public func childNames(_ directory: String) -> [String] { FileSystem.childNames(directory) }
    public func isDirectory(_ path: String) -> Bool { FileSystem.isDirectory(path) }
    public func isSymlink(_ path: String) -> Bool { FileSystem.isSymlink(path) }
    public func exists(_ path: String) -> Bool { FileSystem.exists(path) }
    public func modificationTime(_ path: String) -> Int { FileSystem.modificationTime(path) }
    public func contents(of path: String) -> Data? { FileManager.default.contents(atPath: path) }
    public func remove(_ path: String) throws { try FileManager.default.removeItem(atPath: path) }
}

/// What time it is.
public protocol WallClock: Sendable {
    func now() -> Date
}

public struct SystemClock: WallClock {
    public init() {}
    public func now() -> Date { Date() }
}

extension Tools {
    /// A machine with none of the tools: no simctl, no brew, no Xcode
    /// defaults, no git, nothing running, no Spotlight dates, and a Trash that
    /// refuses. For running the app's model in tests without any process.
    public static var unavailable: Tools {
        Tools(
            simctl: UnavailableTool(),
            brew: UnavailableTool(),
            xcodeDefaults: UnavailableTool(),
            xcodeSelect: UnavailableTool(),
            git: UnavailableTool(),
            runningApps: UnavailableTool(),
            lastUsedDates: UnavailableTool(),
            trash: UnavailableTool())
    }
}

private struct UnavailableTool: SimctlClient, BrewClient, XcodeDefaultsReading, XcodeSelectReading, GitClient,
    RunningAppsChecking, LastUsedDateReading, TrashService
{
    struct Refused: Error {}

    var isAvailable: Bool {
        false
    }

    var isInstalled: Bool {
        false
    }

    func unavailableDevicesListing() async -> String { "" }
    func runtimesJSON() async -> Data? { nil }
    func devicesJSON() async -> Data? { nil }
    func deleteUnavailable() async -> Bool { false }
    func deleteRuntime(_ id: String) async -> Bool { false }
    func cleanupDryRun() async -> String { "" }
    func cleanup() async -> Bool { false }
    func customDerivedDataLocation() async -> String { "" }
    func selectedDeveloperDirectory() async -> String { "" }
    func trackedFiles(in directory: String, named name: String) async -> String? { nil }
    func worktreeList(in directory: String) async -> String? { nil }
    func status(in directory: String) async -> String? { nil }
    func refsContainingHead(in directory: String) async -> String? { nil }
    func headCommitTime(in directory: String) async -> String? { nil }
    func removeWorktree(_ path: String, from repository: String) async -> Bool { false }
    func isRunning(_ app: DeveloperApp) async -> Bool { false }
    func lastUsedDate(of path: String) -> Date? { nil }
    func trash(_ path: String) throws -> String { throw Refused() }
    func putBack(_ trashed: String, to original: String) throws { throw Refused() }
}
