/// The eleven things DevSweep measures and can delete, in report order.
public enum Item: String, CaseIterable, Sendable, Identifiable, Hashable, Codable {
    case derivedData = "derived-data"
    case simulators
    case deviceInstalls = "device-installs"
    case deviceSupport = "device-support"
    case swiftpmCache = "swiftpm-cache"
    case swiftpmBuilds = "swiftpm-builds"
    case xcodeBuilds = "xcode-builds"
    case gradleBuilds = "gradle-builds"
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
        case .npmCache: "npm cache"
        case .homebrew: "Homebrew old versions and downloads"
        case .toolCaches: "Tool caches"
        }
    }

    /// Whether the report shows how many folders it found.
    public var showsCount: Bool {
        switch self {
        case .simulators, .deviceSupport, .swiftpmBuilds, .xcodeBuilds, .gradleBuilds, .toolCaches: true
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
        case .npmCache: .npm
        case .toolCaches, .gradleBuilds: .otherTools
        }
    }

    /// Ids joined the way the bash script lists them in errors.
    public static var idList: String {
        allCases.map(\.rawValue).joined(separator: " ")
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

    /// Items of this family, largest first in a typical home folder, which is
    /// the order the palette assigns them from darker to lighter.
    public var items: [Item] {
        switch self {
        case .xcode: [.derivedData, .deviceSupport, .simulators, .xcodeBuilds, .deviceInstalls]
        case .swiftPackages: [.swiftpmCache, .swiftpmBuilds]
        case .homebrew: [.homebrew]
        case .npm: [.npmCache]
        case .otherTools: [.toolCaches, .gradleBuilds]
        }
    }
}
