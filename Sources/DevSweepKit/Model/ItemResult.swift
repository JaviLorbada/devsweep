/// What one item found: the folders it would delete and how much space they take.
public struct ItemResult: Sendable, Identifiable, Codable, Equatable {
    public var item: Item
    /// Resolved paths, sorted and without duplicates. Each one passed the path
    /// policy when it was listed. Empty for Homebrew, which brew cleans itself.
    public var paths: [String]
    /// Size as the report prints it: the sum of `du -sk` over `paths`, or for
    /// Homebrew what `brew cleanup` says it would free.
    public var kilobytes: Int64
    /// Where the item looks, as the dim line under its row says it.
    public var location: String
    /// The DerivedData breakdown, only for `.derivedData`.
    public var derivedData: DerivedDataBreakdown?
    /// False when a folder could not be read, so the size is a lower bound.
    public var sizeKnown: Bool

    public var id: Item {
        self.item
    }

    public var bytes: Int64 {
        self.kilobytes * 1024
    }

    public var label: String {
        self.item.label(count: self.paths.count)
    }

    /// Items with nothing to reclaim are listed as "none" and never cleaned.
    public var isEmpty: Bool {
        self.kilobytes <= 0
    }

    public init(
        item: Item,
        paths: [String],
        kilobytes: Int64,
        location: String,
        derivedData: DerivedDataBreakdown? = nil,
        sizeKnown: Bool = true)
    {
        self.item = item
        self.paths = paths
        self.kilobytes = kilobytes
        self.location = location
        self.derivedData = derivedData
        self.sizeKnown = sizeKnown
    }
}

/// What DerivedData holds: the caches every project shares, and one folder per project.
public struct DerivedDataBreakdown: Sendable, Equatable, Codable {
    public var compilationCacheKilobytes: Int64
    public var moduleCacheKilobytes: Int64
    public var otherKilobytes: Int64
    /// Largest first, ties in the order `sort` leaves them.
    public var projects: [DerivedDataProject]

    public init(
        compilationCacheKilobytes: Int64 = 0,
        moduleCacheKilobytes: Int64 = 0,
        otherKilobytes: Int64 = 0,
        projects: [DerivedDataProject] = [])
    {
        self.compilationCacheKilobytes = compilationCacheKilobytes
        self.moduleCacheKilobytes = moduleCacheKilobytes
        self.otherKilobytes = otherKilobytes
        self.projects = projects
    }

    public var totalKilobytes: Int64 {
        self.compilationCacheKilobytes + self.moduleCacheKilobytes + self.otherKilobytes
            + self.projects.reduce(0) { $0 + $1.kilobytes }
    }
}

public struct DerivedDataProject: Sendable, Equatable, Identifiable, Codable {
    public enum Status: Sendable, Equatable, Codable {
        /// Last built on this day, `YYYY-MM-DD`.
        case built(String)
        /// The workspace it was built from no longer exists.
        case gone
    }

    /// `Folder/Project`, from the workspace path.
    public var name: String
    public var status: Status
    public var kilobytes: Int64
    /// The project's folder inside DerivedData.
    public var folder: String
    public var workspacePath: String

    public var id: String {
        self.folder
    }

    public init(name: String, status: Status, kilobytes: Int64, folder: String, workspacePath: String) {
        self.name = name
        self.status = status
        self.kilobytes = kilobytes
        self.folder = folder
        self.workspacePath = workspacePath
    }

    public var statusText: String {
        switch self.status {
        case let .built(day): "built \(day)"
        case .gone: "project gone"
        }
    }
}
