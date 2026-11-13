import DevSweepKit
import SwiftUI

struct SidebarView: View {
    @Environment(WindowViewModel.self) private var window
    @Environment(OverviewViewModel.self) private var overview
    @Environment(ScanModel.self) private var scan
    @State private var showsXcode = true
    @State private var showsAndroid = true
    @State private var showsGit = true

    private func row(
        _ title: String,
        kilobytes: Int64?,
        screen: Screen,
        showsZero: Bool = true) -> some View
    {
        HStack {
            Text(title).lineLimit(1)
            Spacer()
            SidebarSize(kilobytes: kilobytes, showsZero: showsZero)
        }
        .tag(screen)
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        @Bindable var window = self.window
        List(selection: $window.screen.optional) {
            Label("Overview", systemImage: "chart.pie")
                .tag(Screen.overview)

            Section("Caches") {
                ForEach(Family.allCases) { family in
                    Button {
                        self.overview.pick(family)
                    } label: {
                        HStack(spacing: 9) {
                            Dot(color: Palette.color(family))
                            Text(family.name).lineLimit(1)
                            Spacer()
                            SidebarSize(kilobytes: self.scan.tally.measuredKilobytes(of: family))
                                .opacity(self.scan.tally.familyShowsPrevious(family) ? 0.5 : 1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Listed, never cleaned: each tool's group under its own heading.
            Section("Also worth a look") {
                DisclosureGroup(isExpanded: self.$showsXcode) {
                    self.row("Versions", kilobytes: self.scan.extras?.xcodesKilobytes, screen: .xcodeVersions)
                    self.row(
                        "Simulator runtimes",
                        kilobytes: self.scan.extras?.runtimesKilobytes,
                        screen: .simulatorRuntimes)
                } label: {
                    Label("Xcode", systemImage: "hammer")
                }
                DisclosureGroup(isExpanded: self.$showsAndroid) {
                    self.row("Versions", kilobytes: self.scan.android?.studiosKilobytes, screen: .androidStudios)
                    self.row("SDK and emulators", kilobytes: self.scan.android?.sdkKilobytes, screen: .androidSDK)
                    self.row(
                        "Gradle caches",
                        kilobytes: self.scan.android?.gradleCachesKilobytes,
                        screen: .gradleCaches)
                } label: {
                    Label("Android Studio", systemImage: "iphone.gen3")
                }
                DisclosureGroup(isExpanded: self.$showsGit) {
                    // What can go, as the caches show; the help says what stays.
                    self.row(
                        "Worktrees",
                        kilobytes: self.scan.extras?.removableWorktreesKilobytes,
                        screen: .worktrees,
                        showsZero: false)
                        .help(self.scan.extras.map { WorktreeWords.summary($0.worktrees) } ?? "Listing worktrees…")
                } label: {
                    Label("Git", systemImage: "arrow.triangle.branch")
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
    /// False leaves a size of zero out rather than saying "Zero KB".
    var showsZero = true

    var body: some View {
        let text = self.kilobytes.map { $0 == 0 && !self.showsZero ? "" : SizeText.of(kilobytes: $0) }
        Text(text ?? "–")
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.muted)
            .contentTransition(.numericText())
    }
}

/// The boot volume: used, reclaimable, free.
struct DiskMeter: View {
    @Environment(ScanModel.self) private var scan

    var body: some View {
        let space = self.scan.diskSpace
        let total = Double(max(space?.totalKilobytes ?? 1, 1))
        let free = Double(space?.freeKilobytes ?? 0)
        let reclaimable = min(Double(scan.tally.reclaimableKilobytes), max(total - free, 0))
        let usedOther = max(total - free - reclaimable, 0)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(self.scan.volumeName).font(.callout.weight(.semibold))
                Spacer()
                if let space {
                    Text(space.freeOfTotal)
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
                Text("\(SizeText.of(kilobytes: self.scan.tally.reclaimableKilobytes)) reclaimable")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.muted)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension Screen {
    /// Lets a non-optional selection drive a List, which wants an optional one.
    var optional: Screen? {
        get { self }
        set { if let newValue { self = newValue } }
    }
}
