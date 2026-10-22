import Foundation

/// The results of a finished scan, kept so the window can show them on the
/// next launch while a new scan runs.
public struct SavedScan: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var date: Date
    /// The resolved home folder the results describe.
    public var home: String
    public var results: [ItemResult]
    public var extras: Extras?
    /// Absent in scans saved before the app listed Android Studio.
    public var android: AndroidReport?

    public init(date: Date, home: String, results: [ItemResult], extras: Extras?, android: AndroidReport? = nil) {
        self.version = Self.currentVersion
        self.date = date
        self.home = home
        self.results = results
        self.extras = extras
        self.android = android
    }
}

/// Where the last scan is kept: one JSON file.
public struct ScanStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `<home>/Library/Application Support/DevClean/last-scan.json`, inside the
    /// home folder the scan describes, so a fake home keeps its own.
    public static func standard(home: String) -> ScanStore {
        ScanStore(url: URL(fileURLWithPath: home)
            .appending(components: "Library", "Application Support", "DevClean", "last-scan.json"))
    }

    /// The saved scan of `home`, or nil when there is none, it can't be read,
    /// it was written by another version, or it describes another folder.
    public func load(home: String) -> SavedScan? {
        guard let data = try? Data(contentsOf: url),
              let scan = try? Self.decoder.decode(SavedScan.self, from: data),
              scan.version == SavedScan.currentVersion,
              scan.home.bytesEqual(home)
        else {
            return nil
        }
        return scan
    }

    public func save(_ scan: SavedScan) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(scan).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
