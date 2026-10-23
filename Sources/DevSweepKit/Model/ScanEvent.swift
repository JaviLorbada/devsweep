/// What a scan reports as it goes. Events arrive in this order:
/// `projectFolders`, then for each item `started`, any `progress` and
/// `warning`, and `finished`; then `done` once every item is measured, and
/// last `extras` and `android` when the scan was asked for them.
public enum ScanEvent: Sendable {
    /// Which project folders get searched, and which were missing or outside home.
    case projectFolders(ProjectFolders)
    case started(Item)
    /// Running total in bytes while the item is measured.
    case progress(Item, bytes: Int64)
    /// Something the user should know, worded as the bash script words it,
    /// without the "<command>: " prefix.
    case warning(String)
    case finished(ItemResult)
    /// Every item is measured. `totalBytes` counts only items with something to reclaim.
    case done(totalBytes: Int64, freeBytes: Int64)
    /// Installed Xcodes and simulator runtimes.
    case extras(Extras)
    /// What Android Studio keeps on disk.
    case android(AndroidReport)
}

/// The project folders a scan searches for build folders.
public struct ProjectFolders: Sendable, Equatable {
    /// Each entry as given, shortened to `~/...`, by what was found there.
    public var found: [String]
    public var missing: [String]
    public var outside: [String]
    /// Resolved folders to search, in the order given.
    public var roots: [String]

    public init(found: [String] = [], missing: [String] = [], outside: [String] = [], roots: [String] = []) {
        self.found = found
        self.missing = missing
        self.outside = outside
        self.roots = roots
    }
}
