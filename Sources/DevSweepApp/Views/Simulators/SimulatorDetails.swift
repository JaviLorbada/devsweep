import DevSweepKit
import SwiftUI

/// What the inspector says about one simulator.
struct SimulatorDetails: View {
    let simulator: Simulator
    let staleDays: Int

    var body: some View {
        let stale = self.simulator.flagReason(staleDays: self.staleDays) != nil
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Dot(color: stale ? .orange : .secondary.opacity(0.6))
                Eyebrow(text: SimulatorWords.kind(self.simulator.deviceSet))
            }
            Text(self.simulator.name).font(.title3.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(SizeText.of(kilobytes: self.simulator.kilobytes))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                Text(SimulatorWords.status(self.simulator, staleDays: self.staleDays))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(stale ? AnyShapeStyle(.orange) : AnyShapeStyle(.muted))
            }
            InspectorSection("Runtime") { Text(self.simulator.runtime) }
            InspectorSection(stale ? "Why it is flagged" : "Usage") { Text(SimulatorWords.usage(self.simulator)) }
            InspectorSection("Size") { Text(SimulatorWords.size) }
            InspectorSection("Where it comes from") { Text(SimulatorWords.origin(self.simulator.deviceSet)) }
            InspectorSection("UDID") {
                Text(self.simulator.id)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, WindowLayout.inspectorTopPadding)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
