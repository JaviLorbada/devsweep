/// A simulator, as `simctl list devices -j` lists it: one of those Xcode and
/// Simulator show, or one Xcode made on its own for previews or tests.
/// DevSweep lists them; it never erases or deletes one.
public struct Simulator: Sendable, Identifiable, Equatable, Codable {
    /// Which of simctl's device sets a simulator is in.
    public enum DeviceSet: String, Sendable, Codable, CaseIterable {
        /// The simulators Xcode and Simulator show.
        case `default`
        /// The ones Xcode makes to show SwiftUI previews.
        case previews
        /// The clones Xcode makes to run tests in parallel.
        case testing

        /// What tells simctl to work in this set.
        var simctlArguments: [String] {
            self == .default ? [] : ["--set", self.rawValue]
        }
    }

    /// Unused for this many days, a simulator is stale.
    public static let staleDays = 30

    /// Its UDID.
    public let id: String
    public let name: String
    /// "iOS 27.1"
    public let runtime: String
    /// "Booted" or "Shutdown", as simctl says it.
    public let state: String
    /// Its data, as simctl measures it: the apps on it and what they keep.
    public let kilobytes: Int64
    /// `YYYY-MM-DD`, nil when never used.
    public let lastUsedDay: String?
    /// Whole days since last use, nil when never used or the date doesn't parse.
    public let daysSinceUsed: Int?
    public let deviceSet: DeviceSet

    public init(
        id: String,
        name: String,
        runtime: String,
        state: String,
        kilobytes: Int64,
        lastUsedDay: String?,
        daysSinceUsed: Int?,
        deviceSet: DeviceSet)
    {
        self.id = id
        self.name = name
        self.runtime = runtime
        self.state = state
        self.kilobytes = kilobytes
        self.lastUsedDay = lastUsedDay
        self.daysSinceUsed = daysSinceUsed
        self.deviceSet = deviceSet
    }

    /// Unused for `staleDays` or more. One never used isn't: it holds little.
    public var isStale: Bool {
        (self.daysSinceUsed ?? 0) >= Self.staleDays
    }

    public var isBooted: Bool {
        self.state == "Booted"
    }
}
