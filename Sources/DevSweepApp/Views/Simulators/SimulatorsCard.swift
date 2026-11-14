import DevSweepKit
import SwiftUI

/// A card of simulators, or a line saying why it has none.
struct SimulatorsCard: View {
    let title: String
    let note: String
    let simulators: [Simulator]
    /// What the card says when it has none.
    let empty: String
    /// The UDID of the one shown selected.
    let selectedID: String?
    let staleDays: Int
    let select: @MainActor (Simulator) -> Void

    var body: some View {
        ExtrasCard(title: self.title, note: self.note, rowCount: self.simulators.count) {
            if self.simulators.isEmpty {
                EmptyExtrasRow(text: self.empty)
            } else {
                let largest = Double(self.simulators.map(\.kilobytes).max() ?? 1)
                ForEach(self.simulators) { simulator in
                    Divider().opacity(0.6)
                    SimulatorRow(
                        simulator: simulator,
                        largest: largest,
                        staleDays: self.staleDays,
                        isSelected: simulator.id == self.selectedID)
                    {
                        self.select(simulator)
                    }
                }
            }
        }
    }
}
