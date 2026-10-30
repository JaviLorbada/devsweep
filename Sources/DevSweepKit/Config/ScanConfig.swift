/// Everything a scan needs to know besides the tools it runs.
public struct ScanConfig: Sendable {
    /// `$HOME` exactly as given. Paths are shortened to `~` against this string,
    /// and checked against its resolved form.
    public var home: String
    /// Folders to search for build folders, as given: `~` is expanded later.
    public var projectDirectories: [String]
    /// Folders to look for installed Xcodes in.
    public var applicationsDirectories: [String]
    public var skipped: Set<Item>
    /// Runtimes unused for this many days get flagged.
    public var staleDays: Int
    /// Whether to list installed Xcodes and simulator runtimes after the items.
    public var includeExtras: Bool
    /// Whether to list what Android Studio keeps. Only the app asks for it;
    /// the command line's report has no such section.
    public var includeAndroid: Bool
    /// Whether to list the git worktrees of repositories in the project
    /// folders with the extras. Run under the original script's name the tool
    /// runs no git for them, so its report and tool calls stay the script's.
    public var includeWorktrees: Bool
    /// The environment the scan runs in. Git's `GIT_DIR` and `GIT_WORK_TREE`
    /// come from here.
    public var environment: [String: String]

    public init(
        home: String,
        projectDirectories: [String],
        applicationsDirectories: [String],
        skipped: Set<Item> = [],
        staleDays: Int = 90,
        includeExtras: Bool = true,
        includeAndroid: Bool = false,
        includeWorktrees: Bool = false,
        environment: [String: String] = [:])
    {
        self.home = home
        self.projectDirectories = projectDirectories
        self.applicationsDirectories = applicationsDirectories
        self.skipped = skipped
        self.staleDays = staleDays
        self.includeExtras = includeExtras
        self.includeAndroid = includeAndroid
        self.includeWorktrees = includeWorktrees
        self.environment = environment
    }

    /// The configuration the bash script derives from its environment:
    /// `HOME`, `<PREFIX>_PROJECT_DIRS` and `<PREFIX>_APPLICATIONS_DIRS`, the prefix being the command name's, with
    /// `--projects` taking precedence. Empty variables count as unset.
    public static func fromEnvironment(
        _ environment: [String: String],
        projects: String? = nil,
        skipped: Set<Item> = [],
        includeExtras: Bool = true,
        command: CommandName = .product) -> ScanConfig
    {
        let home = environment["HOME"] ?? ""
        let projectList = projects
            ?? environment[command.variable("PROJECT_DIRS")].flatMap { $0.isEmpty ? nil : $0 }
            ?? self.defaultProjectDirectories(home: home)
        let applicationsList = environment[command.variable("APPLICATIONS_DIRS")].flatMap { $0.isEmpty ? nil : $0 }
            ?? "/Applications:\(home)/Applications"
        return ScanConfig(
            home: home,
            projectDirectories: self.splitList(projectList),
            applicationsDirectories: self.splitList(applicationsList),
            skipped: skipped,
            includeExtras: includeExtras,
            includeWorktrees: includeExtras && command == .product,
            environment: environment)
    }

    public static func defaultProjectDirectories(home: String) -> String {
        ["Developer", "Development", "dev", "Documents/Workspace", "Projects"]
            .map { "\(home)/\($0)" }
            .joined(separator: ":")
    }

    /// Splits a colon-separated list the way the script reads it, one entry per
    /// line after `tr ':' '\n'`, dropping empty entries.
    public static func splitList(_ list: String) -> [String] {
        list.split(omittingEmptySubsequences: true) { $0 == ":" || $0 == "\n" }.map(String.init)
    }

    /// Parses `--skip`: whitespace is ignored, so "a, b" and "a,b" mean the same.
    /// Throws for the first id that isn't an item.
    public static func parseSkip(_ value: String) throws(PreflightError) -> Set<Item> {
        let compact = String(value.unicodeScalars.filter { !" \t\n\u{0B}\u{0C}\r".unicodeScalars.contains($0) })
        var items = Set<Item>()
        for id in compact.split(separator: ",", omittingEmptySubsequences: true) {
            guard let item = Item(rawValue: String(id)) else {
                throw .unknownItem(String(id))
            }
            items.insert(item)
        }
        return items
    }

    /// True when the four items Xcode or Simulator may be using are all skipped.
    public var skipsEverythingXcodeUses: Bool {
        Item.allCases.filter(\.needsXcodeClosed).allSatisfy(self.skipped.contains)
    }
}
