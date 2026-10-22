import Foundation
import Synchronization

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

/// Where the last scan is kept between launches.
public protocol ScanMemoryStore: Sendable {
    /// The saved scan of `home`, or nil when there is none or it can't be used.
    func load(home: String) -> SavedScan?
    func save(_ scan: SavedScan) throws
}

/// Kept in memory only, for tests.
public final class InMemoryScanStore: ScanMemoryStore {
    private let scan = Mutex<SavedScan?>(nil)

    public init() {}

    public func load(home: String) -> SavedScan? {
        self.scan.withLock { $0 }.flatMap { $0.home.bytesEqual(home) ? $0 : nil }
    }

    public func save(_ scan: SavedScan) throws {
        self.scan.withLock { $0 = scan }
    }
}

/// Where the last scan is kept: one JSON file.
public struct ScanStore: ScanMemoryStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `<home>/Library/Application Support/DevClean/last-scan.json`, inside the
    /// home folder the scan describes, so a fake home keeps its own.
    public static func standard(home: String) -> ScanStore {
        ScanStore(url: URL(fileURLWithPath: home)
            .appending(
                components: "Library",
                "Application Support",
                ProductInfo.applicationSupportFolder,
                "last-scan.json"))
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
        try FileManager.default.createDirectory(
            at: self.url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Self.encoder.encode(scan).write(to: self.url, options: .atomic)
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
