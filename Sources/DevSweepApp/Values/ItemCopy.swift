import DevSweepKit
import Foundation

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
            "Build products, indexes and the shared compilation and module caches. Xcode rebuilds them on the next "
                + "build, so the first build after cleaning is slower."
        case .swiftpmCache:
            "Shared clones of every package you have resolved. The next package resolve downloads what it needs again."
        case .deviceSupport:
            "Debug symbols for OS versions your devices no longer run. The newest version per device model stays; "
                + "Xcode copies symbols again when a device connects."
        case .simulators:
            "Simulator devices whose iOS version is no longer installed, so they cannot boot. Removed through "
                + "simctl, never with rm, so they can't be put back."
        case .swiftpmBuilds:
            "Build output of local packages. Folders tracked in git are skipped. Comes back on the next swift build."
        case .homebrew:
            "Outdated formula versions and the download cache. Homebrew measures and removes these itself, so they "
                + "can't be put back."
        case .xcodeBuilds:
            "Output xcodebuild left next to a project. Only folders holding real Xcode output count; other folders "
                + "called build are left alone."
        case .npmCache:
            "Downloaded packages and npx runs. npm fetches again on the next install."
        case .deviceInstalls:
            "Cached app installs for physical devices. Rebuilt on the next install to a device."
        case .toolCaches:
            "Download caches of CocoaPods, Carthage, Sourcery, Playwright and JetBrains Toolbox. Each tool downloads "
                + "again when needed."
        case .gradleBuilds:
            "Build output next to a Gradle file. Gradle rebuilds it on the next build."
        }
    }

    /// Items whose own tool deletes them, so the Trash can't hold them.
    var cleanedByItsTool: Bool {
        self == .simulators || self == .homebrew
    }

    /// Whether the inspector lists its folders to tick one by one, as it
    /// does DerivedData's parts.
    var cleansByFolder: Bool {
        self == .swiftpmBuilds || self == .xcodeBuilds || self == .gradleBuilds
    }

    /// Whether Xcode builds into it, so cleaning part of it while Xcode is
    /// open asks first: Xcode may have that project open.
    var xcodeBuildsInto: Bool {
        self == .derivedData || self == .xcodeBuilds
    }
}

extension SizeText {
    /// A disk's capacity, in whole gigabytes once it is that big: "995 GB".
    static func wholeGigabytes(kilobytes: Int64) -> String {
        let bytes = kilobytes * 1024
        return bytes >= 999_500_000 ? "\((bytes + 500_000_000) / 1_000_000_000) GB" : self.of(bytes: bytes)
    }
}
