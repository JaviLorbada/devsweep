import DevSweepKit

/// The words the Simulators screen uses.
enum SimulatorWords {
    /// "98 days unused", for a simulator flagged after `staleDays`; nil for
    /// one that isn't.
    static func badge(_ simulator: Simulator, staleDays: Int) -> String? {
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

    /// "looks unused" for a flagged one, otherwise simctl's state in words:
    /// "booted", "shut down".
    static func status(_ simulator: Simulator, staleDays: Int) -> String {
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

    /// What a simulator's size is.
    static let size = "Its data, as simctl measures it: the apps installed on it and what they keep."
}
