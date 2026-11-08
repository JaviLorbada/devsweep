import DevSweepKit
import Observation

/// The simulator runtimes screen's own state: the runtime selected, the
/// removal sheet, and what the screen says under its title.
@MainActor
@Observable
final class RuntimesViewModel {
    /// The runtime selected, by its simctl id.
    private(set) var selectedID: String?
    let removal = Removal<SimulatorRuntime>()
    private let scan: ScanModel
    private let preferences: Preferences

    init(scan: ScanModel, preferences: Preferences) {
        self.scan = scan
        self.preferences = preferences
    }

    var runtimes: [SimulatorRuntime] {
        self.scan.extras?.runtimes ?? []
    }

    /// Days unused before a runtime is flagged.
    var staleDays: Int {
        self.preferences.staleDays
    }

    /// The selected runtime, or the first flagged one, or the first.
    var current: SimulatorRuntime? {
        self.runtimes.first { $0.id == self.selectedID }
            ?? self.runtimes.first { $0.flagReason(staleDays: self.staleDays) != nil }
            ?? self.runtimes.first
    }

    func select(_ runtime: SimulatorRuntime) {
        self.selectedID = runtime.id
    }

    /// Selects `runtime` and opens the removal sheet for it.
    func askToRemove(_ runtime: SimulatorRuntime) {
        self.select(runtime)
        self.removal.ask(runtime)
    }

    /// Removes the runtime on the sheet through simctl, then lists runtimes again.
    func remove(_ runtime: SimulatorRuntime) async {
        let removed = await self.removal.run(
            runtime,
            failure: "simctl couldn't remove it. Run the command in Terminal to see why; a simulator using it may "
                + "still be running.",
            remove: self.scan.removeRuntime)
        if removed { self.selectedID = nil }
    }

    var subtitle: String {
        StatusText.runtimes(self.scan.extras?.runtimes, isLoading: self.scan.isLoadingExtras)
    }
}
