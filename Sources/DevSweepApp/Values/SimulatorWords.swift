import DevSweepKit

/// The words the Simulators screen uses.
enum SimulatorWords {
    /// "runtime gone" for a simulator that can't run, "98 days unused" for
    /// one flagged after `staleDays`, nil for the others.
    static func badge(_ simulator: Simulator, staleDays: Int) -> String? {
        guard simulator.isAvailable else {
            return "runtime gone"
        }
        guard simulator.flagReason(staleDays: staleDays) != nil, let days = simulator.daysSinceUsed else {
            return nil
        }
        return days == 1 ? "1 day unused" : "\(days) days unused"
    }

    /// "iOS 27.1", and "iOS 27.1, for previews" for one Xcode made on its own.
    static func detail(_ simulator: Simulator) -> String {
        switch simulator.deviceSet {
        case .default: simulator.runtime
        case .previews: "\(simulator.runtime), for previews"
        case .testing: "\(simulator.runtime), for tests"
        }
    }

    /// When it was last used.
    static func usage(_ simulator: Simulator) -> String {
        guard let day = simulator.lastUsedDay else {
            return "Never used."
        }
        switch simulator.daysSinceUsed {
        case let days? where days == 1: return "Last used on \(day), 1 day ago."
        case let days? where days > 1: return "Last used on \(day), \(days) days ago."
        default: return "Last used on \(day)."
        }
    }

    /// "used 2026-07-08", or "never used".
    static func lastUse(_ simulator: Simulator) -> String {
        simulator.lastUsedDay.map { "used \($0)" } ?? "never used"
    }

    /// What VoiceOver reads for a row: its name, its size and its badge.
    static func label(_ simulator: Simulator, staleDays: Int) -> String {
        let named = "\(simulator.name), \(SizeText.of(kilobytes: simulator.kilobytes))"
        return self.badge(simulator, staleDays: staleDays).map { "\(named), \($0)" } ?? named
    }

    /// The inspector's heading over the last use: why it's flagged, when it is.
    static func usageHeading(_ simulator: Simulator, staleDays: Int) -> String {
        simulator.flagReason(staleDays: staleDays) == nil ? "Usage" : "Why it is flagged"
    }

    /// "runtime gone" for one that can't run, "looks unused" for a flagged
    /// one, otherwise simctl's state in words: "booted", "shut down".
    static func status(_ simulator: Simulator, staleDays: Int) -> String {
        if !simulator.isAvailable {
            return "runtime gone"
        }
        if simulator.flagReason(staleDays: staleDays) != nil {
            return "looks unused"
        }
        return simulator.state == "Shutdown" ? "shut down" : simulator.state.lowercased()
    }

    /// What the inspector calls a simulator in each set.
    static func kind(_ set: Simulator.DeviceSet) -> String {
        switch set {
        case .default: "Simulator"
        case .previews: "Previews simulator"
        case .testing: "Test clone"
        }
    }

    /// Where a simulator in each set comes from.
    static func origin(_ set: Simulator.DeviceSet) -> String {
        switch set {
        case .default: "One of the simulators Xcode and Simulator show."
        case .previews: "Xcode made it to show SwiftUI previews, and makes another when a preview needs one."
        case .testing: "Xcode cloned it to run tests in parallel, and clones another when tests need one."
        }
    }

    /// What happens to a simulator whose runtime is gone. The Overview's
    /// Simulators item cleans only the default set.
    static func runtimeGone(_ set: Simulator.DeviceSet) -> String {
        let gone = "Its runtime is gone, so it can't run."
        return switch set {
        case .default: "\(gone) The Overview's Simulators item removes it, with xcrun simctl delete unavailable."
        case .previews, .testing:
            "\(gone) \(ProductInfo.name) leaves it: xcrun simctl --set \(set.rawValue) delete unavailable removes it."
        }
    }

    /// What a simulator's size is.
    static let size = "Its data, as simctl measures it: the apps installed on it and what they keep."
}
