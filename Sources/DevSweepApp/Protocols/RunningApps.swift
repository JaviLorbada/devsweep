import DevSweepKit

/// Whether Xcode and Simulator are open, and quitting them before a clean
/// that needs them closed.
///
/// `RunningAppsModel` conforms. `CleaningModel` and `OverviewViewModel`
/// take it.
@MainActor
protocol RunningApps: AnyObject {
    /// The ones open when last looked.
    var running: Set<DeveloperApp> { get }
    /// Looks again.
    func refresh() async
    /// Asks `apps` to quit and waits for them. Whether they all did.
    func quit(_ apps: [DeveloperApp]) async -> Bool
}

extension RunningApps {
    /// The open ones, in a fixed order: what a clean asks to quit.
    var open: [DeveloperApp] {
        DeveloperApp.allCases.filter(self.running.contains)
    }

    /// "Xcode is open."
    var sentence: String {
        StatusText.runningApps(self.running)
    }
}
