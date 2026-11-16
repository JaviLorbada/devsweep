import Foundation

/// The product's names and version, in one place with `version.env`, so a new
/// name or version is a change to these two files.
public enum ProductInfo {
    /// The app's name, in the menu bar, the window and the text.
    public static let name = "DevSweep"
    /// The command line tool's name, in its usage and messages.
    public static let cliName = "devsweep"
    /// The prefix of the tool's environment variables: `DEVSWEEP_PROJECT_DIRS`.
    public static let environmentPrefix = "DEVSWEEP"
    public static let bundleIdentifier = "com.javilorbada.devsweep"
    /// The folder in `~/Library/Application Support` the app keeps its last
    /// scan in: DevSweep, or DevSweep Dev for a development build.
    public static var applicationSupportFolder: String {
        BuildIdentity.current.supportFolder
    }

    /// The app's UserDefaults domain: its bundle's standard defaults.
    public static let defaultsSuite = bundleIdentifier

    /// The version, as in `version.env`; a test keeps the two equal. The
    /// command line tool has no Info.plist to read it from, so the app's
    /// About and `devsweep --version` both read it here.
    public static let version = "0.7.1"

    /// The build number, as in `version.env`: when the release was cut, in UTC.
    public static let build = "202611162305"

    /// Where the project lives; the About window and the Help menu link here.
    public static let repository = URL(string: "https://github.com/JaviLorbada/devsweep")!
    /// Where to report a problem.
    public static let issues = repository.appending(path: "issues")
    /// The MIT license the project is under.
    public static let license = repository.appending(path: "blob/main/LICENSE")
    /// Where to sponsor the project, from About.
    public static let sponsor = URL(string: "https://github.com/sponsors/JaviLorbada")!
    /// A tip jar, from About and the Help menu.
    public static let tipJar = URL(string: "https://ko-fi.com/javilorbada")!
}

/// The name the command line tool answers to, and its environment variables'
/// prefix. Run as `devsweep` it is DevSweep's tool. Run under the original
/// bash script's name, `devclean`, it is that script word for word: its name
/// in every message and its `DEVCLEAN_` variables. That is how the script's
/// bats suite and the side-by-side comparison run it.
public struct CommandName: Sendable, Equatable {
    public let name: String
    public let environmentPrefix: String

    public static let product = CommandName(name: ProductInfo.cliName, environmentPrefix: ProductInfo.environmentPrefix)
    /// The bash script this tool replaces.
    public static let original = CommandName(name: "devclean", environmentPrefix: "DEVCLEAN")

    /// The name for a tool started as `path`, its `argv[0]`.
    public static func invoked(as path: String) -> CommandName {
        FileSystem.basename(path) == self.original.name ? .original : .product
    }

    /// `DEVSWEEP_PROJECT_DIRS` for `PROJECT_DIRS`.
    public func variable(_ name: String) -> String {
        "\(self.environmentPrefix)_\(name)"
    }
}
