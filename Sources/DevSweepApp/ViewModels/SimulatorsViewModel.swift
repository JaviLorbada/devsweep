import DevSweepKit
import Observation

/// The Simulators screen's own state: the simulator selected, and what the
/// screen says under its title and on its cards.
@MainActor
@Observable
final class SimulatorsViewModel {
    /// The simulator selected, by its UDID.
    private(set) var selectedID: String?
    private let scan: any Listings
    private let preferences: Preferences

    init(scan: any Listings, preferences: Preferences) {
        self.scan = scan
        self.preferences = preferences
    }

    /// Days unused before a simulator is flagged: the setting runtimes use.
    var staleDays: Int {
        self.preferences.staleDays
    }

    /// What the Simulators card says beside its title.
    var note: String {
        "flagged after \(self.staleDays) days unused"
    }

    /// What the Simulators card and the inspector say when there are none.
    var noSimulators: String {
        self.scan.isLoadingExtras ? "Listing simulators…" : "No simulators found."
    }

    /// What the Previews and tests card says when there are none.
    var noPreviewsOrTests: String {
        self.scan.isLoadingExtras ? "Listing simulators…" : "Xcode made none for previews or tests."
    }

    /// The simulators Xcode and Simulator show, the largest first.
    var simulators: [Simulator] {
        self.all.filter { $0.deviceSet == .default }
    }

    /// The ones Xcode made on its own, for SwiftUI previews and for running
    /// tests in parallel, the largest first.
    var previewsAndTests: [Simulator] {
        self.all.filter { $0.deviceSet != .default }
    }

    /// The selected simulator, or the first flagged one, or the first, in
    /// the order the screen lists them.
    var current: Simulator? {
        let listed = self.simulators + self.previewsAndTests
        return listed.first { $0.id == self.selectedID }
            ?? listed.first { $0.flagReason(staleDays: self.staleDays) != nil }
            ?? listed.first
    }

    func select(_ simulator: Simulator) {
        self.selectedID = simulator.id
    }

    var subtitle: String {
        StatusText.simulators(
            self.scan.extras?.simulators,
            staleDays: self.staleDays,
            isLoading: self.scan.isLoadingExtras)
    }

    private var all: [Simulator] {
        self.scan.extras?.simulators ?? []
    }
}
