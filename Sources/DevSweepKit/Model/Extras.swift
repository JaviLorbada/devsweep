import Foundation

/// Things the report lists but the tool never deletes.
public struct Extras: Sendable, Codable, Equatable {
    public var xcodes: [InstalledXcode]
    public var runtimes: [SimulatorRuntime]

    public init(xcodes: [InstalledXcode] = [], runtimes: [SimulatorRuntime] = []) {
        self.xcodes = xcodes
        self.runtimes = runtimes
    }
}

public struct InstalledXcode: Sendable, Identifiable, Equatable, Codable {
    /// The app as found, not resolved.
    public var path: String
    public var version: String
    public var build: String
    public var kilobytes: Int64
    public var lastOpened: Date?
    /// The one `xcode-select -p` points at.
    public var isSelected: Bool

    public var id: String {
        self.path
    }

    public var title: String {
        "Xcode \(self.version) (\(self.build))"
    }

    public init(path: String, version: String, build: String, kilobytes: Int64, lastOpened: Date?, isSelected: Bool) {
        self.path = path
        self.version = version
        self.build = build
        self.kilobytes = kilobytes
        self.lastOpened = lastOpened
        self.isSelected = isSelected
    }

    /// "opened 2026-10-20, selected", as the report prints it.
    public var note: String {
        var note = self.lastOpened.map { "opened \(DayFormat.utc($0))" } ?? "last opened unknown"
        if self.isSelected { note += ", selected" }
        return note
    }
}

public struct SimulatorRuntime: Sendable, Identifiable, Equatable, Codable {
    /// The id `simctl runtime delete` takes.
    public var id: String
    public var identifier: String
    public var platform: String
    public var version: String
    public var build: String
    public var kilobytes: Int64
    /// `YYYY-MM-DD`, nil when never used.
    public var lastUsedDay: String?
    /// Whole days since last use, nil when never used or the date doesn't parse.
    public var daysSinceUsed: Int?
    public var simulatorCount: Int

    public init(
        id: String,
        identifier: String,
        platform: String,
        version: String,
        build: String,
        kilobytes: Int64,
        lastUsedDay: String?,
        daysSinceUsed: Int?,
        simulatorCount: Int)
    {
        self.id = id
        self.identifier = identifier
        self.platform = platform
        self.version = version
        self.build = build
        self.kilobytes = kilobytes
        self.lastUsedDay = lastUsedDay
        self.daysSinceUsed = daysSinceUsed
        self.simulatorCount = simulatorCount
    }

    public var title: String {
        "\(self.platform) \(self.version) (\(self.build))"
    }

    /// The command that removes it. DevSweep shows it; it never runs it unasked.
    public var removalCommand: String {
        "xcrun simctl runtime delete \(self.id)"
    }

    /// "used 2026-10-20, 2 simulators"
    public var note: String {
        let used = self.lastUsedDay.map { "used \($0)" } ?? "never used"
        return self.simulatorCount == 1 ? "\(used), 1 simulator" : "\(used), \(self.simulatorCount) simulators"
    }

    /// Why it looks unused, or nil when it doesn't.
    public func flagReason(staleDays: Int) -> String? {
        var reason: String?
        if let days = daysSinceUsed, days >= staleDays {
            reason = "Not used in \(days) days"
        }
        if self.simulatorCount == 0 {
            reason = reason.map { "\($0), no simulators" } ?? "No simulators"
        }
        return reason
    }
}
