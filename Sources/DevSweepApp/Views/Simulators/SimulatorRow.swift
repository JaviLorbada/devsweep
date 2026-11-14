import DevSweepKit
import SwiftUI

/// A simulator: its name, runtime, last use and size, flagged when stale.
struct SimulatorRow: View {
    @Environment(WindowViewModel.self) private var window
    @Environment(SimulatorsViewModel.self) private var simulators
    @Environment(\.extrasColumns) private var columns
    let simulator: Simulator
    let largest: Double

    var body: some View {
        let badge = SimulatorWords.badge(self.simulator)
        let selected = self.window.screen == .simulators && self.simulators.current?.id == self.simulator.id
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
                Text(self.simulator.lastUsedDay.map { "used \($0)" } ?? "never used")
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
            selected: selected,
            label: "\(self.simulator.name), \(SizeText.of(kilobytes: self.simulator.kilobytes))"
                + (badge.map { ", \($0)" } ?? ""))
        {
            self.simulators.select(self.simulator)
        }
    }
}
