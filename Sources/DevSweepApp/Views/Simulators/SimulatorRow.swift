import DevSweepKit
import SwiftUI

/// A simulator: its name, runtime, last use and size, flagged when its
/// runtime is gone or it is unused for `staleDays`.
struct SimulatorRow: View {
    @Environment(\.extrasColumns) private var columns
    let simulator: Simulator
    /// The card's largest, which fills the bar.
    let largest: Double
    let staleDays: Int
    let isSelected: Bool
    let select: @MainActor () -> Void

    var body: some View {
        let badge = SimulatorWords.badge(self.simulator, staleDays: self.staleDays)
        let tint: Color = badge == nil ? .secondary.opacity(0.6) : .orange
        HStack(spacing: 12) {
            Dot(color: tint)
            // The runtime and the badge give way first, then the name truncates.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.simulator.name).fontWeight(.medium).lineLimit(1).layoutPriority(2)
                Text(SimulatorWords.detail(self.simulator))
                    .font(.caption)
                    .foregroundStyle(.muted)
                    .lineLimit(1)
                if let badge {
                    Badge(text: badge, color: .orange)
                } else if self.simulator.isBooted {
                    Badge(text: "booted", color: .accentColor)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if self.columns.showsDate {
                Text(SimulatorWords.lastUse(self.simulator))
                    .font(.callout)
                    .foregroundStyle(.muted)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)
            }
            if self.columns.showsBar {
                ThinBar(fraction: Double(self.simulator.kilobytes) / max(self.largest, 1), color: tint)
                    .frame(width: 100)
            }
            Text(SizeText.of(kilobytes: self.simulator.kilobytes))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
        }
        .selectableRow(
            selected: self.isSelected,
            label: SimulatorWords.label(self.simulator, staleDays: self.staleDays),
            select: self.select)
    }
}
