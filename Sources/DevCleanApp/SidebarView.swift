import DevCleanKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.screen.optional) {
            Label("Overview", systemImage: "chart.pie")
                .tag(AppModel.Screen.overview)

            Section("Caches") {
                ForEach(Family.allCases) { family in
                    Button {
                        model.pick(family)
                    } label: {
                        HStack(spacing: 9) {
                            Dot(color: Palette.color(family))
                            Text(family.name).lineLimit(1)
                            Spacer()
                            SidebarSize(kilobytes: model.measuredKilobytes(of: family))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Also worth a look") {
                HStack {
                    Text("Xcode versions")
                    Spacer()
                    SidebarSize(kilobytes: model.xcodesKilobytes)
                }
                .tag(AppModel.Screen.xcodeVersions)
                HStack {
                    Text("Simulator runtimes")
                    Spacer()
                    SidebarSize(kilobytes: model.runtimesKilobytes)
                }
                .tag(AppModel.Screen.simulatorRuntimes)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            DiskMeter()
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }
}

private struct SidebarSize: View {
    let kilobytes: Int64?

    var body: some View {
        Text(kilobytes.map { SizeText.of(kilobytes: $0) } ?? "–")
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
    }
}

/// The boot volume: used, reclaimable, free.
struct DiskMeter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let space = model.diskSpace
        let total = Double(max(space?.totalKilobytes ?? 1, 1))
        let free = Double(space?.availableKilobytes ?? 0)
        let reclaimable = min(Double(model.reclaimableKilobytes), max(total - free, 0))
        let usedOther = max(total - free - reclaimable, 0)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.volumeName).font(.callout.weight(.semibold))
                Spacer()
                if let space {
                    Text("\(SizeText.of(kilobytes: space.availableKilobytes)) free of \(SizeText.wholeGigabytes(kilobytes: space.totalKilobytes))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                }
            }
            GeometryReader { proxy in
                let width = proxy.size.width - 4
                HStack(spacing: 2) {
                    Rectangle().fill(.primary.opacity(0.22)).frame(width: width * usedOther / total)
                    Rectangle().fill(Palette.reclaimable).frame(width: width * reclaimable / total)
                    Rectangle().fill(.primary.opacity(0.07))
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            .animation(.easeInOut(duration: 0.4), value: reclaimable)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Palette.reclaimable).frame(width: 8, height: 8)
                Text("\(SizeText.of(kilobytes: model.reclaimableKilobytes)) reclaimable")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension AppModel.Screen {
    /// Lets a non-optional selection drive a List, which wants an optional one.
    var optional: AppModel.Screen? {
        get { self }
        set { if let newValue { self = newValue } }
    }
}
