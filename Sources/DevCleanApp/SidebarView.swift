import DevCleanKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var showsXcode = true
    @State private var showsAndroid = true

    private func row(_ title: String, kilobytes: Int64?, screen: AppModel.Screen) -> some View {
        HStack {
            Text(title).lineLimit(1)
            Spacer()
            SidebarSize(kilobytes: kilobytes)
        }
        .tag(screen)
        .accessibilityElement(children: .combine)
    }

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
                                .opacity(model.familyShowsPrevious(family) ? 0.5 : 1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Listed, never cleaned: each tool's group under its own heading.
            Section("Also worth a look") {
                DisclosureGroup(isExpanded: self.$showsXcode) {
                    self.row("Versions", kilobytes: model.xcodesKilobytes, screen: .xcodeVersions)
                    self.row("Simulator runtimes", kilobytes: model.runtimesKilobytes, screen: .simulatorRuntimes)
                } label: {
                    Label("Xcode", systemImage: "hammer")
                }
                DisclosureGroup(isExpanded: self.$showsAndroid) {
                    self.row("Versions", kilobytes: model.androidStudiosKilobytes, screen: .androidStudios)
                    self.row("SDK and emulators", kilobytes: model.androidSDKKilobytes, screen: .androidSDK)
                    self.row("Gradle caches", kilobytes: model.gradleCachesKilobytes, screen: .gradleCaches)
                } label: {
                    Label("Android Studio", systemImage: "iphone.gen3")
                }
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
        Text(self.kilobytes.map { SizeText.of(kilobytes: $0) } ?? "–")
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.muted)
            .contentTransition(.numericText())
    }
}

/// The boot volume: used, reclaimable, free.
struct DiskMeter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let space = self.model.diskSpace
        let total = Double(max(space?.totalKilobytes ?? 1, 1))
        let free = Double(space?.availableKilobytes ?? 0)
        let reclaimable = min(Double(model.reclaimableKilobytes), max(total - free, 0))
        let usedOther = max(total - free - reclaimable, 0)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(self.model.volumeName).font(.callout.weight(.semibold))
                Spacer()
                if let space {
                    Text(
                        "\(SizeText.of(kilobytes: space.availableKilobytes)) free of "
                            + "\(SizeText.wholeGigabytes(kilobytes: space.totalKilobytes))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.muted)
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
            .animation(Motion.animation(.easeInOut(duration: 0.4)), value: reclaimable)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Palette.reclaimable).frame(width: 8, height: 8)
                Text("\(SizeText.of(kilobytes: self.model.reclaimableKilobytes)) reclaimable")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.muted)
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
