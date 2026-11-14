import DevSweepKit
import SwiftUI

/// The simulators Xcode and Simulator show, then the ones Xcode made on its own.
struct SimulatorsContent: View {
    @Environment(SimulatorsViewModel.self) private var simulators
    @Environment(ScanModel.self) private var scan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SimulatorsCard(
                title: "Simulators",
                note: "flagged after \(self.simulators.staleDays) days unused",
                simulators: self.simulators.simulators,
                empty: self.scan.isLoadingExtras ? "Listing simulators…" : "No simulators found.")
            SimulatorsCard(
                title: "Previews and tests",
                note: "made by Xcode on its own",
                simulators: self.simulators.previewsAndTests,
                empty: self.scan.isLoadingExtras ? "Listing simulators…" : "Xcode made none for previews or tests.")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
}
