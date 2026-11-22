import SwiftUI

/// The simulator selected, or why there is none.
struct SimulatorInspector: View {
    @Environment(SimulatorsViewModel.self) private var simulators

    var body: some View {
        if let simulator = self.simulators.current {
            // Scrolls, so the column never asks the window for the height of
            // its text: at a small width that would be thousands of points.
            ScrollView {
                SimulatorDetails(simulator: simulator, staleDays: self.simulators.staleDays)
            }
        } else {
            ContentUnavailableView(
                "No simulator",
                systemImage: "iphone",
                description: Text(self.simulators.noSimulators))
        }
    }
}
