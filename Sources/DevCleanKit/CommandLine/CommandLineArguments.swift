/// The command line options, read with the bash script's rules.
public struct CommandLineOptions: Sendable, Equatable {
    public var run = false
    public var yes = false
    public var skip: String?
    public var projects: String?

    public init(run: Bool = false, yes: Bool = false, skip: String? = nil, projects: String? = nil) {
        self.run = run
        self.yes = yes
        self.skip = skip
        self.projects = projects
    }

    public enum Outcome: Sendable, Equatable {
        case help
        case failure(String)
        case options(CommandLineOptions)
    }

    /// Reads arguments left to right, as the script did: the first unknown
    /// option fails, `--help` wins only if nothing before it failed, and
    /// `--skip` and `--projects` take the next argument whatever it is.
    public static func check(_ arguments: [String]) -> Outcome {
        var options = CommandLineOptions()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--run":
                options.run = true
            case "-y", "--yes":
                options.yes = true
            case "--skip", "--projects":
                guard index + 1 < arguments.count else { return .failure("Missing value for \(argument)") }
                index += 1
                if argument == "--skip" { options.skip = arguments[index] } else { options.projects = arguments[index] }
            case "-h", "--help":
                return .help
            default:
                return .failure("Unknown option: \(argument) (see \(ProductInfo.cliName) --help)")
            }
            index += 1
        }
        return .options(options)
    }

    /// The same options spelled so any parser accepts them: each at most once,
    /// values in their own argument.
    public var arguments: [String] {
        var arguments: [String] = []
        if self.run { arguments.append("--run") }
        if self.yes { arguments.append("--yes") }
        if let skip { arguments += ["--skip", skip] }
        if let projects { arguments += ["--projects", projects] }
        return arguments
    }

    public static let usage = """
    Usage: \(ProductInfo.cliName) [--run [--yes]] [--skip ITEMS] [--projects DIRS]

    Shows how much space developer caches take up. With --run, deletes them.
    Everything listed is rebuilt or downloaded again when needed; the cost is
    slower first builds and package resolves afterwards.

    Options:
      --run            Delete the items in the report (asks first)
      -y, --yes        Don't ask for confirmation (with --run)
      --skip ITEMS     Comma-separated items to leave alone,
                       e.g. --skip swiftpm-cache,homebrew
      --projects DIRS  Colon-separated folders to search for build folders.
                       Default: $DEVCLEAN_PROJECT_DIRS if set, otherwise
                       ~/Developer:~/Development:~/dev:~/Documents/Workspace:~/Projects
      -h, --help       Show this help

    Items:
      derived-data     Xcode DerivedData, including the compilation cache
      simulators       Simulators whose iOS version is no longer installed
      device-installs  Cached app installs for physical devices
      device-support   Device debug symbols, except the newest version for
                       each device model (Xcode copies them again on connect)
      swiftpm-cache    SwiftPM's shared package clones
      swiftpm-builds   .build folders next to a Package.swift
      xcode-builds     build folders with Xcode output, next to an Xcode
                       project, workspace or Package.swift
      gradle-builds    build folders next to a Gradle build file
      npm-cache        npm's download cache
      homebrew         Old Homebrew versions and downloads
      tool-caches      CocoaPods, Carthage, Sourcery, Playwright and
                       JetBrains Toolbox caches

    The report breaks DerivedData down into the shared compilation and module
    caches and each project's folder, with its last build date, flagging
    projects that no longer exist.

    The report also lists installed Xcodes and simulator runtimes, and flags
    runtimes unused for 90+ days. \(ProductInfo.cliName) never deletes those; it shows how
    to remove them yourself.

    Never touched: Xcode Archives (their dSYMs symbolicate crash reports),
    simulators that still work, simulator runtimes, build folders tracked in
    git, and anything outside your home folder.

    """
}
