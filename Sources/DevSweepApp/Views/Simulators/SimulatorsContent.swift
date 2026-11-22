import SwiftUI

/// The simulators Xcode and Simulator show, then the ones Xcode made on its own.
struct SimulatorsContent: View {
    @Environment(SimulatorsViewModel.self) private var simulators

    var body: some View {
        let selectedID = self.simulators.current?.id
        VStack(alignment: .leading, spacing: 14) {
            SimulatorsCard(
                title: "Simulators",
                note: self.simulators.note,
                simulators: self.simulators.simulators,
                empty: self.simulators.noSimulators,
                selectedID: selectedID,
                staleDays: self.simulators.staleDays,
                select: self.simulators.select)
            SimulatorsCard(
                title: "Previews and tests",
                note: "made by Xcode on its own",
                simulators: self.simulators.previewsAndTests,
                empty: self.simulators.noPreviewsOrTests,
                selectedID: selectedID,
                staleDays: self.simulators.staleDays,
                select: self.simulators.select)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
}
