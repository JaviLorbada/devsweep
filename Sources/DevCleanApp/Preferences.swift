import DevCleanKit
import Foundation
import Observation

/// Where preferences are kept: UserDefaults in the app, memory in tests.
protocol PreferenceStorage: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: PreferenceStorage {}

/// A dictionary, so tests never write the real defaults.
final class MemoryPreferenceStorage: PreferenceStorage {
    private var values: [String: Any] = [:]

    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
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

    @ObservationIgnored private let storage: PreferenceStorage

    /// Folders to search for build folders, `~` for home.
    var projectFolders: [String] {
        didSet { storage.set(projectFolders, forKey: Key.projectFolders) }
    }
    /// Items the app leaves out of its scans.
    var skippedItems: Set<Item> {
        didSet { storage.set(skippedItems.map(\.rawValue).sorted(), forKey: Key.skippedItems) }
    }
    /// Runtimes, system images and emulators unused this many days get flagged.
    var staleDays: Int {
        didSet { storage.set(staleDays, forKey: Key.staleDays) }
    }
    /// Whether cleaning starts out moving to the Trash rather than deleting.
    var moveToTrash: Bool {
        didSet { storage.set(moveToTrash, forKey: Key.moveToTrash) }
    }
    var scanOnLaunch: Bool {
        didSet { storage.set(scanOnLaunch, forKey: Key.scanOnLaunch) }
    }
    /// A notification when DerivedData grew by more than this since the last scan.
    var derivedDataGrowthGigabytes: Int {
        didSet { storage.set(derivedDataGrowthGigabytes, forKey: Key.derivedDataGrowthGigabytes) }
    }

    init(storage: PreferenceStorage = UserDefaults.standard) {
        self.storage = storage
        projectFolders = storage.object(forKey: Key.projectFolders) as? [String] ?? Self.defaultProjectFolders
        skippedItems = Set((storage.object(forKey: Key.skippedItems) as? [String] ?? []).compactMap(Item.init(rawValue:)))
        let days = storage.object(forKey: Key.staleDays) as? Int ?? Self.defaultStaleDays
        staleDays = min(max(days, Self.staleDaysRange.lowerBound), Self.staleDaysRange.upperBound)
        moveToTrash = storage.object(forKey: Key.moveToTrash) as? Bool ?? true
        scanOnLaunch = storage.object(forKey: Key.scanOnLaunch) as? Bool ?? true
        let growth = storage.object(forKey: Key.derivedDataGrowthGigabytes) as? Int ?? Self.defaultGrowthGigabytes
        derivedDataGrowthGigabytes = min(max(growth, Self.growthRange.lowerBound), Self.growthRange.upperBound)
    }

    var usesDefaultProjectFolders: Bool { projectFolders == Self.defaultProjectFolders }

    func restoreDefaultProjectFolders() {
        projectFolders = Self.defaultProjectFolders
    }

    /// Adds a folder, written with `~` when it is inside home.
    func addProjectFolder(_ path: String, home: String) {
        var folder = path
        if !home.isEmpty, folder == home || folder.hasPrefix(home + "/") {
            folder = "~" + folder.dropFirst(home.count)
        }
        guard !projectFolders.contains(folder) else { return }
        projectFolders.append(folder)
    }

    /// The scan settings these preferences make, on top of what the
    /// environment says. `DEVCLEAN_PROJECT_DIRS`, when set, still wins, as it
    /// does for the command line.
    func scanConfig(environment: [String: String]) -> ScanConfig {
        let fromEnvironment = environment["DEVCLEAN_PROJECT_DIRS"].flatMap { $0.isEmpty ? nil : $0 }
        var config = ScanConfig.fromEnvironment(environment, projects: fromEnvironment ?? projectFolders.joined(separator: ":"))
        config.skipped = skippedItems
        config.staleDays = staleDays
        config.includeAndroid = true
        return config
    }
}
