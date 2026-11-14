/// Every outside tool the engine uses, injected so tests can replace each one.
public struct Tools: Sendable {
    public var simctl: any SimctlClient
    public var brew: any BrewClient
    public var xcodeDefaults: any XcodeDefaultsReading
    public var xcodeSelect: any XcodeSelectReading
    public var git: any GitClient
    public var runningApps: any RunningAppsChecking
    public var lastUsedDates: any LastUsedDateReading
    public var trash: any TrashService
    public var freeSpace: any FreeSpaceReading

    public init(
        simctl: any SimctlClient,
        brew: any BrewClient,
        xcodeDefaults: any XcodeDefaultsReading,
        xcodeSelect: any XcodeSelectReading,
        git: any GitClient,
        runningApps: any RunningAppsChecking,
        lastUsedDates: any LastUsedDateReading,
        trash: any TrashService,
        freeSpace: any FreeSpaceReading)
    {
        self.simctl = simctl
        self.brew = brew
        self.xcodeDefaults = xcodeDefaults
        self.xcodeSelect = xcodeSelect
        self.git = git
        self.runningApps = runningApps
        self.lastUsedDates = lastUsedDates
        self.trash = trash
        self.freeSpace = freeSpace
    }

    /// The real tools, found through the environment's `PATH`.
    /// - Parameters:
    ///   - passthroughOutput: let `simctl delete` print to the terminal.
    ///   - command: under the original script's name, free space is read the
    ///     script's way, through `osascript`; otherwise macOS is asked directly.
    public static func live(
        environment: [String: String],
        passthroughOutput: Bool = false,
        command: CommandName = .product) -> Tools
    {
        let runner = LiveProcessRunner(environment: environment)
        return Tools(
            simctl: LiveSimctlClient(runner: runner, passthroughDeletes: passthroughOutput),
            brew: LiveBrewClient(runner: runner),
            xcodeDefaults: LiveXcodeDefaults(runner: runner),
            xcodeSelect: LiveXcodeSelect(runner: runner),
            git: LiveGitClient(runner: runner),
            runningApps: PgrepRunningApps(runner: runner),
            lastUsedDates: SpotlightLastUsedDates(),
            trash: SystemTrash(),
            freeSpace: command == .original ? OsascriptFreeSpace(runner: runner) : SystemFreeSpace())
    }
}
