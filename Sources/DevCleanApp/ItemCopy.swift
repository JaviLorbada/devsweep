import DevCleanKit

/// The words the window uses for each item.
extension Item {
    /// Short enough for "Clean ..." buttons, the scan capsule and treemap cells.
    var shortName: String {
        switch self {
        case .derivedData: "DerivedData"
        case .simulators: "Simulators"
        case .deviceInstalls: "Device install cache"
        case .deviceSupport: "Device Support"
        case .swiftpmCache: "SwiftPM cache"
        case .swiftpmBuilds: ".build folders"
        case .xcodeBuilds: "Xcode build folders"
        case .gradleBuilds: "Gradle build folders"
        case .npmCache: "npm cache"
        case .homebrew: "Homebrew"
        case .toolCaches: "Tool caches"
        }
    }

    /// What cleaning it does, for the inspector.
    var whatHappens: String {
        switch self {
        case .derivedData:
            "Build products, indexes and the shared compilation and module caches. Xcode rebuilds them on the next build, so the first build after cleaning is slower."
        case .swiftpmCache:
            "Shared clones of every package you have resolved. The next package resolve downloads what it needs again."
        case .deviceSupport:
            "Debug symbols for OS versions your devices no longer run. The newest version per device model stays; Xcode copies symbols again when a device connects."
        case .simulators:
            "Simulator devices whose iOS version is no longer installed, so they cannot boot. Removed through simctl, never with rm, so they can't be put back."
        case .swiftpmBuilds:
            "Build output of local packages. Folders tracked in git are skipped. Comes back on the next swift build."
        case .homebrew:
            "Outdated formula versions and the download cache. Homebrew measures and removes these itself, so they can't be put back."
        case .xcodeBuilds:
            "Output xcodebuild left next to a project. Only folders holding real Xcode output count; other folders called build are left alone."
        case .npmCache:
            "Downloaded packages and npx runs. npm fetches again on the next install."
        case .deviceInstalls:
            "Cached app installs for physical devices. Rebuilt on the next install to a device."
        case .toolCaches:
            "Download caches of CocoaPods, Carthage, Sourcery, Playwright and JetBrains Toolbox. Each tool downloads again when needed."
        case .gradleBuilds:
            "Build output next to a Gradle file. Gradle rebuilds it on the next build."
        }
    }

    /// Items whose own tool deletes them, so the Trash can't hold them.
    var cleanedByItsTool: Bool {
        self == .simulators || self == .homebrew
    }
}

enum SizeText {
    /// The report's format: binary multiples with decimal labels.
    static func of(kilobytes: Int64) -> String {
        Report.human(kilobytes: max(0, kilobytes))
    }

    static func of(bytes: Int64) -> String {
        Report.human(bytes: max(0, bytes))
    }

    /// A disk's capacity, in whole gigabytes once it is that big: "926 GB".
    static func wholeGigabytes(kilobytes: Int64) -> String {
        kilobytes >= 1_048_576 ? "\(Int((Double(kilobytes) / 1_048_576).rounded())) GB" : self.of(kilobytes: kilobytes)
    }
}
