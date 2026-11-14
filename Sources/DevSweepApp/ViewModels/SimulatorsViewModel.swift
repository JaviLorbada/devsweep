import DevSweepKit
import Observation

/// The Simulators screen's own state: the simulator selected and what the
/// screen says under its title.
@MainActor
@Observable
final class SimulatorsViewModel {
    /// The simulator selected, by its UDID.
    private(set) var selectedID: String?
    private let scan: any Listings

    init(scan: any Listings) {
        self.scan = scan
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

    /// The selected simulator, or the first stale one, or the first, in the
    /// order the screen lists them.
    var current: Simulator? {
        let listed = self.simulators + self.previewsAndTests
        return listed.first { $0.id == self.selectedID } ?? listed.first(where: \.isStale) ?? listed.first
    }

    func select(_ simulator: Simulator) {
        self.selectedID = simulator.id
    }

    var subtitle: String {
        StatusText.simulators(self.scan.extras?.simulators, isLoading: self.scan.isLoadingExtras)
    }

    private var all: [Simulator] {
        self.scan.extras?.simulators ?? []
    }
}
