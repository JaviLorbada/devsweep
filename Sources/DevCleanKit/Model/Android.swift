import Foundation

/// What Android Studio keeps on disk: its installs, the SDK, emulators and
/// Gradle's shared caches. The app lists all of it; nothing here is deleted.
public struct AndroidReport: Sendable, Codable, Equatable {
    /// Android Studio apps in the applications folders.
    public var studios: [AndroidEntry]
    /// The SDK folder, `~/Library/Android/sdk`, when there is one.
    public var sdk: String?
    public var systemImages: [AndroidEntry]
    public var platforms: [AndroidEntry]
    public var buildTools: [AndroidEntry]
    /// Everything else at the top of the SDK: the emulator, platform tools, sources.
    public var otherSDKParts: [AndroidEntry]
    /// Virtual devices in `~/.android/avd`.
    public var emulators: [AndroidEntry]
    /// Folders in `~/.gradle`.
    public var gradleCaches: [AndroidEntry]

    public init(
        studios: [AndroidEntry] = [],
        sdk: String? = nil,
        systemImages: [AndroidEntry] = [],
        platforms: [AndroidEntry] = [],
        buildTools: [AndroidEntry] = [],
        otherSDKParts: [AndroidEntry] = [],
        emulators: [AndroidEntry] = [],
        gradleCaches: [AndroidEntry] = []
    ) {
        self.studios = studios
        self.sdk = sdk
        self.systemImages = systemImages
        self.platforms = platforms
        self.buildTools = buildTools
        self.otherSDKParts = otherSDKParts
        self.emulators = emulators
        self.gradleCaches = gradleCaches
    }

    /// Everything in the SDK folder.
    public var sdkEntries: [AndroidEntry] { systemImages + platforms + buildTools + otherSDKParts }
    public var all: [AndroidEntry] { studios + sdkEntries + emulators + gradleCaches }
}

/// One thing Android Studio keeps: an install, a part of the SDK, an
/// emulator or a Gradle cache folder.
public struct AndroidEntry: Sendable, Codable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case studio
        case systemImage
        case platform
        case buildTools
        case sdkPart
        case emulator
        case gradleCache
    }

    public var kind: Kind
    /// Where it is. Inside home, the path resolved through the path policy,
    /// which is what a clean step would take.
    public var path: String
    public var title: String
    public var detail: String
    public var kilobytes: Int64
    /// Last use, read from modification dates; for an install, when it was
    /// last opened.
    public var lastUsed: Date?
    /// For a system image, how many emulators run on it.
    public var emulatorCount: Int?

    public var id: String { path }

    public init(
        kind: Kind,
        path: String,
        title: String,
        detail: String = "",
        kilobytes: Int64,
        lastUsed: Date? = nil,
        emulatorCount: Int? = nil
    ) {
        self.kind = kind
        self.path = path
        self.title = title
        self.detail = detail
        self.kilobytes = kilobytes
        self.lastUsed = lastUsed
        self.emulatorCount = emulatorCount
    }

    /// Whole days since it was last used.
    public func daysUnused(now: Date = Date()) -> Int? {
        lastUsed.map { max(0, Int((now.timeIntervalSince($0) / 86_400).rounded(.down))) }
    }

    /// Why it looks unused, or nil when it doesn't. Only system images and
    /// emulators are flagged, after `staleDays` without a change on disk.
    public func flagReason(staleDays: Int, now: Date = Date()) -> String? {
        guard kind == .systemImage || kind == .emulator, let days = daysUnused(now: now), days >= staleDays else { return nil }
        return "Not used in \(days) days"
    }
}
