import AppKit
import DevCleanKit
import SwiftUI

/// The menu bar item: the boot volume's free space.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text("\(Image(systemName: "internaldrive")) \(model.diskSpace.map { SizeText.of(kilobytes: $0.availableKilobytes) } ?? "")")
            .accessibilityLabel(model.diskSpace.map { "\(SizeText.of(kilobytes: $0.availableKilobytes)) free" } ?? "DevClean")
    }
}

/// What the menu bar item opens: what the last scan found per family, when
/// that was, and the two things to do from here. It sits on a material that
/// shows the desktop through, so its quieter text is the system's vibrant
/// secondary rather than the window's muted color.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.volumeName).font(.headline)
                Spacer()
                if let space = model.diskSpace {
                    Text("\(SizeText.of(kilobytes: space.availableKilobytes)) free")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 6) {
                ForEach(Family.allCases) { family in
                    HStack(spacing: 8) {
                        Dot(color: Palette.color(family))
                        Text(family.name)
                        Spacer()
                        Text(model.measuredKilobytes(of: family).map { SizeText.of(kilobytes: $0) } ?? "–")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .accessibilityElement(children: .combine)
                }
                Divider()
                HStack {
                    Text("Reclaimable").fontWeight(.semibold)
                    Spacer()
                    Text(SizeText.of(kilobytes: model.reclaimableKilobytes)).fontWeight(.semibold).monospacedDigit()
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
            }
            Text(model.menuBarStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(model.isScanning ? "Scanning…" : "Scan Now") { model.scan() }
                    .disabled(model.isScanning || model.isCleaning || model.engine == nil)
                Spacer()
                Button("Open DevClean") {
                    openWindow(id: "main")
                    NSApplication.shared.activate()
                }
                .buttonStyle(.glassProminent)
            }
            .controlSize(.large)
        }
        .padding(16)
        .frame(width: 280)
    }
}

extension AppModel {
    /// "Last scanned 3 hours ago." under the totals, or what is happening.
    var menuBarStatus: String {
        if isScanning { return "Scanning, \(measuredCount) of \(scanOrder.count) items measured." }
        if let lastScan { return "Last scanned \(Self.relative(lastScan, to: now)). Scans again a day later while DevClean runs." }
        if let previousScanDate { return "Last scanned \(Self.relative(previousScanDate, to: now))." }
        return "Not scanned yet."
    }
}
