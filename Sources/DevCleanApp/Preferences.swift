import DevCleanKit
import Foundation
import Observation

/// Where preferences are kept: UserDefaults in the app, memory in tests.
protocol PreferencesStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: PreferencesStore {}

/// A dictionary, so tests never write the real defaults.
final class InMemoryPreferencesStore: PreferencesStore {
    private var values: [String: Any] = [:]

    func object(forKey key: String) -> Any? { self.values[key] }
    func set(_ value: Any?, forKey key: String) { self.values[key] = value }
}

/// What the Settings window changes. The command line reads none of it: it
/// keeps its environment variables and flags.
@MainActor
@Observable
final class Preferences {
    enum Key {
        static let projectFolders = "projectFolders"
        static let skippedItems = "skippedItems"
        static let staleDays = "staleDays"
        static let moveToTrash = "moveToTrash"
        static let scanOnLaunch = "scanOnLaunch"
        static let derivedDataGrowthGigabytes = "derivedDataGrowthGigabytes"
    }

    /// Today's defaults, the folders the script searches.
    static let defaultProjectFolders = ["~/Developer", "~/Development", "~/dev", "~/Documents/Workspace", "~/Projects"]
    static let defaultStaleDays = 90
    static let staleDaysRange = 7...730
    static let defaultGrowthGigabytes = 20
    static let growthRange = 1...500

    @ObservationIgnored private let storage: PreferencesStore

    /// Folders to search for build folders, `~` for home.
    var projectFolders: [String] {
        didSet { self.storage.set(self.projectFolders, forKey: Key.projectFolders) }
    }

    /// Items the app leaves out of its scans.
    var skippedItems: Set<Item> {
        didSet { self.storage.set(self.skippedItems.map(\.rawValue).sorted(), forKey: Key.skippedItems) }
    }

    /// Runtimes, system images and emulators unused this many days get flagged.
    var staleDays: Int {
        didSet { self.storage.set(self.staleDays, forKey: Key.staleDays) }
    }

    /// Whether cleaning starts out moving to the Trash rather than deleting.
    var moveToTrash: Bool {
        didSet { self.storage.set(self.moveToTrash, forKey: Key.moveToTrash) }
    }

    var scanOnLaunch: Bool {
        didSet { self.storage.set(self.scanOnLaunch, forKey: Key.scanOnLaunch) }
    }

    /// A notification when DerivedData grew by more than this since the last scan.
    var derivedDataGrowthGigabytes: Int {
        didSet { self.storage.set(self.derivedDataGrowthGigabytes, forKey: Key.derivedDataGrowthGigabytes) }
    }

    init(storage: PreferencesStore = UserDefaults.standard) {
        self.storage = storage
        self.projectFolders = storage.object(forKey: Key.projectFolders) as? [String] ?? Self.defaultProjectFolders
        self
            .skippedItems = Set((storage.object(forKey: Key.skippedItems) as? [String] ?? [])
                .compactMap(Item.init(rawValue:)))
        let days = storage.object(forKey: Key.staleDays) as? Int ?? Self.defaultStaleDays
        self.staleDays = min(max(days, Self.staleDaysRange.lowerBound), Self.staleDaysRange.upperBound)
        self.moveToTrash = storage.object(forKey: Key.moveToTrash) as? Bool ?? true
        self.scanOnLaunch = storage.object(forKey: Key.scanOnLaunch) as? Bool ?? true
        let growth = storage.object(forKey: Key.derivedDataGrowthGigabytes) as? Int ?? Self.defaultGrowthGigabytes
        self.derivedDataGrowthGigabytes = min(max(growth, Self.growthRange.lowerBound), Self.growthRange.upperBound)
    }

    var usesDefaultProjectFolders: Bool {
        self.projectFolders == Self.defaultProjectFolders
    }

    func restoreDefaultProjectFolders() {
        self.projectFolders = Self.defaultProjectFolders
    }

    /// Adds a folder, written with `~` when it is inside home.
    func addProjectFolder(_ path: String, home: String) {
        var folder = path
        if !home.isEmpty, folder == home || folder.hasPrefix(home + "/") {
            folder = "~" + folder.dropFirst(home.count)
        }
        guard !self.projectFolders.contains(folder) else { return }
        self.projectFolders.append(folder)
    }

    /// The scan settings these preferences make, on top of what the
    /// environment says. `DEVCLEAN_PROJECT_DIRS`, when set, still wins, as it
    /// does for the command line.
    func scanConfig(environment: [String: String]) -> ScanConfig {
        let fromEnvironment = environment["DEVCLEAN_PROJECT_DIRS"].flatMap { $0.isEmpty ? nil : $0 }
        var config = ScanConfig.fromEnvironment(
            environment,
            projects: fromEnvironment ?? self.projectFolders.joined(separator: ":"))
        config.skipped = self.skippedItems
        config.staleDays = self.staleDays
        config.includeAndroid = true
        return config
    }
}
