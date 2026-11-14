import SwiftUI

/// The simulators Xcode and Simulator show, then the ones Xcode made on its own.
struct SimulatorsContent: View {
    @Environment(WindowViewModel.self) private var window
    @Environment(SimulatorsViewModel.self) private var simulators
    @Environment(ScanModel.self) private var scan

    var body: some View {
        let selectedID = self.window.screen == .simulators ? self.simulators.current?.id : nil
        VStack(alignment: .leading, spacing: 14) {
            SimulatorsCard(
                title: "Simulators",
                note: "flagged after \(self.simulators.staleDays) days unused",
                simulators: self.simulators.simulators,
                empty: self.scan.isLoadingExtras ? "Listing simulators…" : "No simulators found.",
                selectedID: selectedID,
                staleDays: self.simulators.staleDays,
                select: self.simulators.select)
            SimulatorsCard(
                title: "Previews and tests",
                note: "made by Xcode on its own",
                simulators: self.simulators.previewsAndTests,
                empty: self.scan.isLoadingExtras ? "Listing simulators…" : "Xcode made none for previews or tests.",
                selectedID: selectedID,
                staleDays: self.simulators.staleDays,
                select: self.simulators.select)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
}
