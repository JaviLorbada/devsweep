/// The fourteen things DevSweep measures and can delete, in report order.
public enum Item: String, CaseIterable, Sendable, Identifiable, Hashable, Codable {
    case derivedData = "derived-data"
    case simulators
    case deviceInstalls = "device-installs"
    case deviceSupport = "device-support"
    case swiftpmCache = "swiftpm-cache"
    case swiftpmBuilds = "swiftpm-builds"
    case xcodeBuilds = "xcode-builds"
    case gradleBuilds = "gradle-builds"
    case cocoapodsPods = "cocoapods-pods"
    case cargoBuilds = "cargo-builds"
    case nodeModules = "node-modules"
    case npmCache = "npm-cache"
    case homebrew
    case toolCaches = "tool-caches"

    public var id: String {
        rawValue
    }

    /// The name the report prints.
    public var name: String {
        switch self {
        case .derivedData: "Xcode DerivedData"
        case .simulators: "Simulators without a runtime"
        case .deviceInstalls: "Device install cache"
        case .deviceSupport: "Old Device Support"
        case .swiftpmCache: "SwiftPM package cache"
        case .swiftpmBuilds: "SwiftPM .build folders"
        case .xcodeBuilds: "Xcode build folders"
        case .gradleBuilds: "Gradle build folders"
        case .cocoapodsPods: "CocoaPods Pods folders"
        case .cargoBuilds: "Cargo target folders"
        case .nodeModules: "node_modules folders"
        case .npmCache: "npm cache"
        case .homebrew: "Homebrew old versions and downloads"
        case .toolCaches: "Tool caches"
        }
    }

    /// Whether the report shows how many folders it found.
    public var showsCount: Bool {
        switch self {
        case .simulators, .deviceSupport, .swiftpmBuilds, .xcodeBuilds, .gradleBuilds, .cocoapodsPods, .cargoBuilds,
             .nodeModules, .toolCaches: true
        default: false
        }
    }

    /// Item name, with how many folders it found when that's useful.
    public func label(count: Int) -> String {
        self.showsCount && count > 0 ? "\(self.name) (\(count))" : self.name
    }

    /// Items that Xcode or Simulator may be using while they run.
    public var needsXcodeClosed: Bool {
        switch self {
        case .derivedData, .simulators, .deviceInstalls, .deviceSupport: true
        default: false
        }
    }

    public var family: Family {
        switch self {
        case .derivedData, .deviceSupport, .simulators, .xcodeBuilds, .deviceInstalls: .xcode
        case .swiftpmCache, .swiftpmBuilds: .swiftPackages
        case .homebrew: .homebrew
        case .npmCache, .nodeModules: .npm
        case .toolCaches, .gradleBuilds, .cocoapodsPods, .cargoBuilds: .otherTools
        }
    }

    /// Whether the bash script has it. Run under the script's name, the tool
    /// knows only these, so its report, `--skip` and errors stay the script's.
    public var isInOriginalScript: Bool {
        switch self {
        case .derivedData, .simulators, .deviceInstalls, .deviceSupport, .swiftpmCache, .swiftpmBuilds, .xcodeBuilds,
             .gradleBuilds, .npmCache, .homebrew, .toolCaches: true
        case .cocoapodsPods, .cargoBuilds, .nodeModules: false
        }
    }

    /// The items `command` knows, in report order.
    public static func known(by command: CommandName) -> [Item] {
        command == .original ? allCases.filter(\.isInOriginalScript) : allCases
    }

    /// The ids `command` knows, joined the way the bash script lists them in errors.
    public static func idList(for command: CommandName) -> String {
        self.known(by: command).map(\.rawValue).joined(separator: " ")
    }
}

/// The five groups the app colors and charts items by.
public enum Family: String, CaseIterable, Sendable, Identifiable, Hashable, Codable {
    case xcode
    case swiftPackages
    case homebrew
    case npm
    case otherTools

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .xcode: "Xcode"
        case .swiftPackages: "Swift packages"
        case .homebrew: "Homebrew"
        case .npm: "npm"
        case .otherTools: "Other tools"
        }
    }

    /// Items of this family in the order the palette steps them, darker to
    /// lighter: largest first in a typical home folder, except that items
    /// added to a family later took darker steps, so the others kept their
    /// colors.
    public var items: [Item] {
        switch self {
        case .xcode: [.derivedData, .deviceSupport, .simulators, .xcodeBuilds, .deviceInstalls]
        case .swiftPackages: [.swiftpmCache, .swiftpmBuilds]
        case .homebrew: [.homebrew]
        case .npm: [.nodeModules, .npmCache]
        case .otherTools: [.cargoBuilds, .cocoapodsPods, .toolCaches, .gradleBuilds]
        }
    }
}
