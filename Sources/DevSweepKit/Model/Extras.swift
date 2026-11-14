import Foundation

/// Things the report lists but the tool never deletes.
public struct Extras: Sendable, Codable, Equatable {
    public var xcodes: [InstalledXcode]
    public var runtimes: [SimulatorRuntime]
    public var worktrees: [GitWorktree]

    public init(xcodes: [InstalledXcode] = [], runtimes: [SimulatorRuntime] = [], worktrees: [GitWorktree] = []) {
        self.xcodes = xcodes
        self.runtimes = runtimes
        self.worktrees = worktrees
    }

    enum CodingKeys: String, CodingKey {
        case xcodes, runtimes, worktrees
    }

    /// Scans saved before worktrees were listed have none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.xcodes = try container.decode([InstalledXcode].self, forKey: .xcodes)
        self.runtimes = try container.decode([SimulatorRuntime].self, forKey: .runtimes)
        self.worktrees = try container.decodeIfPresent([GitWorktree].self, forKey: .worktrees) ?? []
    }
}

/// A linked git worktree: a second working copy of a repository, the kind
/// coding tools make for each task and leave behind. Its dependencies and
/// build output can make it large. DevSweep removes one only when asked, with
/// git's own `worktree remove`, and only when nothing in it would be lost.
public struct GitWorktree: Sendable, Identifiable, Equatable, Codable {
    /// The worktree's folder, as git lists it.
    public var path: String
    /// The repository's main working copy, which git runs in to remove it.
    public var repository: String
    /// The branch checked out, nil when HEAD is detached.
    public var branch: String?
    public var kilobytes: Int64
    public var lastCommit: Date?
    /// Files changed or not tracked, as `git status --porcelain` lists them;
    /// nil when git couldn't tell.
    public var changes: Int?
    /// Whether a branch or a remote branch holds every commit in it, so that
    /// removing it loses none.
    public var commitsKept: Bool
    public var isLocked: Bool

    public init(
        path: String,
        repository: String,
        branch: String?,
        kilobytes: Int64,
        lastCommit: Date?,
        changes: Int?,
        commitsKept: Bool,
        isLocked: Bool)
    {
        self.path = path
        self.repository = repository
        self.branch = branch
        self.kilobytes = kilobytes
        self.lastCommit = lastCommit
        self.changes = changes
        self.commitsKept = commitsKept
        self.isLocked = isLocked
    }

    public var id: String {
        self.path
    }

    /// The worktree's folder name, with its parent's when it is just the
    /// repository's name, as when a tool keeps each task's checkout in a
    /// folder of its own: `fix-login/App` rather than `App`.
    public var name: String {
        let folder = FileSystem.basename(self.path)
        guard folder == self.repositoryName else { return folder }
        return "\(FileSystem.basename(FileSystem.dirname(self.path)))/\(folder)"
    }

    /// The repository's folder name.
    public var repositoryName: String {
        FileSystem.basename(self.repository)
    }

    /// Why DevSweep keeps it, or nil when it may be removed.
    public var keptBecause: String? {
        if self.isLocked { return "Locked" }
        guard let changes else { return "Couldn't check it for changes" }
        if changes == 1 { return "1 change not committed" }
        if changes > 1 { return "\(changes) changes not committed" }
        if !self.commitsKept { return "Commits on no branch" }
        return nil
    }

    /// The command that removes it, the one DevSweep runs when asked, with
    /// paths from `~/` where that reads the same.
    public func removalCommand(policy: PathPolicy) -> String {
        "git -C \(ShellWord.path(self.repository, policy: policy)) worktree remove "
            + ShellWord.path(self.path, policy: policy)
    }

    /// "kite, branch main, last commit 2026-10-21", as the report prints it.
    public var note: String {
        var note = "\(self.repositoryName), " + (self.branch.map { "branch \($0)" } ?? "detached")
        if let lastCommit { note += ", last commit \(DayFormat.utc(lastCommit))" }
        return note
    }
}

/// A word as a shell reads it: as it is when it has nothing the shell would
/// change, otherwise in single quotes.
enum ShellWord {
    static func quoted(_ word: String) -> String {
        self.isPlain(word) ? word : "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Whether the shell reads `word` as it is.
    static func isPlain(_ word: some StringProtocol) -> Bool {
        !word.isEmpty && word.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "/._-+@%:,=".unicodeScalars.contains($0)
        }
    }

    /// A path as a shell command shows it: from `~/` when that reads the same,
    /// quoted when it has to be.
    static func path(_ path: String, policy: PathPolicy) -> String {
        let short = policy.tilde(path)
        if short.hasPrefix("~/"), self.isPlain(short.dropFirst(2)) { return short }
        return self.quoted(path)
    }
}

public struct InstalledXcode: Sendable, Identifiable, Equatable, Codable {
    /// The app as found, not resolved.
    public var path: String
    public var version: String
    public var build: String
    public var kilobytes: Int64
    public var lastOpened: Date?
    /// The one `xcode-select -p` points at.
    public var isSelected: Bool

    public var id: String {
        self.path
    }

    public var title: String {
        "Xcode \(self.version) (\(self.build))"
    }

    public init(path: String, version: String, build: String, kilobytes: Int64, lastOpened: Date?, isSelected: Bool) {
        self.path = path
        self.version = version
        self.build = build
        self.kilobytes = kilobytes
        self.lastOpened = lastOpened
        self.isSelected = isSelected
    }

    /// "opened 2026-10-20, selected", as the report prints it.
    public var note: String {
        var note = self.lastOpened.map { "opened \(DayFormat.utc($0))" } ?? "last opened unknown"
        if self.isSelected { note += ", selected" }
        return note
    }
}

public struct SimulatorRuntime: Sendable, Identifiable, Equatable, Codable {
    /// The id `simctl runtime delete` takes.
    public var id: String
    public var identifier: String
    public var platform: String
    public var version: String
    public var build: String
    /// What removing it frees: simctl's size, plus the download macOS keeps
    /// for it when the scan counts it.
    public var kilobytes: Int64
    /// The download macOS keeps for it, which simctl's size leaves out and
    /// `simctl runtime delete` removes with it; counted in `kilobytes`. Nil
    /// when it has none of its own, or the scan doesn't count it.
    public let downloadKilobytes: Int64?
    /// `YYYY-MM-DD`, nil when never used.
    public var lastUsedDay: String?
    /// Whole days since last use, nil when never used or the date doesn't parse.
    public var daysSinceUsed: Int?
    public var simulatorCount: Int

    public init(
        id: String,
        identifier: String,
        platform: String,
        version: String,
        build: String,
        kilobytes: Int64,
        lastUsedDay: String?,
        daysSinceUsed: Int?,
        simulatorCount: Int,
        downloadKilobytes: Int64? = nil)
    {
        self.id = id
        self.identifier = identifier
        self.platform = platform
        self.version = version
        self.build = build
        self.kilobytes = kilobytes
        self.downloadKilobytes = downloadKilobytes
        self.lastUsedDay = lastUsedDay
        self.daysSinceUsed = daysSinceUsed
        self.simulatorCount = simulatorCount
    }

    public var title: String {
        "\(self.platform) \(self.version) (\(self.build))"
    }

    /// The same runtime with the download macOS keeps for it counted in its size.
    func counting(downloadKilobytes download: Int64) -> SimulatorRuntime {
        SimulatorRuntime(
            id: self.id,
            identifier: self.identifier,
            platform: self.platform,
            version: self.version,
            build: self.build,
            kilobytes: self.kilobytes + download,
            lastUsedDay: self.lastUsedDay,
            daysSinceUsed: self.daysSinceUsed,
            simulatorCount: self.simulatorCount,
            downloadKilobytes: download)
    }

    /// The command that removes it. DevSweep shows it; it never runs it unasked.
    public var removalCommand: String {
        "xcrun simctl runtime delete \(self.id)"
    }

    /// "used 2026-10-20, 2 simulators"
    public var note: String {
        let used = self.lastUsedDay.map { "used \($0)" } ?? "never used"
        return self.simulatorCount == 1 ? "\(used), 1 simulator" : "\(used), \(self.simulatorCount) simulators"
    }

    /// Why it looks unused, or nil when it doesn't.
    public func flagReason(staleDays: Int) -> String? {
        var reason: String?
        if let days = daysSinceUsed, days >= staleDays {
            reason = "Not used in \(days) days"
        }
        if self.simulatorCount == 0 {
            reason = reason.map { "\($0), no simulators" } ?? "No simulators"
        }
        return reason
    }
}
