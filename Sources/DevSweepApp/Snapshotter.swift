#if DEBUG
import AppKit
import DevSweepKit
import SwiftUI

/// Development aid: with `DEVSWEEP_SNAPSHOT=/path/file.png` set, waits for the
/// scan to finish, draws the window's content into that file and quits.
/// `DEVSWEEP_SNAPSHOT_SCREEN` picks `overview`, `scanning`, `blocks`, `runtimes`,
/// `xcodes`, `about` (the About window's content), `menubar` (the menu bar
/// item's panel), `remove-runtime` (shows the removal sheet, never confirms it),
/// `cleaned` (cleans what is marked first) or `putback` (then puts
/// the SwiftPM cache back). Cleaning must only ever run against a fake home,
/// with `DEVSWEEP_TRASH_FOLDER` set;
/// `DEVSWEEP_SNAPSHOT_APPEARANCE` picks `dark` or `light`;
/// `DEVSWEEP_SNAPSHOT_SELECT` picks an item id or runtime id to select;
/// `DEVSWEEP_SNAPSHOT_WIDTH` lays it out that wide instead of 1280, without
/// the inspector where the window would hide it.
///
/// The window itself can't be captured without screen recording permission,
/// so this draws the same content views with ImageRenderer, laid out like the
/// window. System controls that AppKit draws come out as placeholders.
enum Snapshotter {
    @MainActor
    static func runIfAsked(_ model: AppModel) async {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["DEVSWEEP_SNAPSHOT"] else { return }
        let dark = environment["DEVSWEEP_SNAPSHOT_APPEARANCE"] != "light"
        NSApplication.shared.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        while model.scan.isScanning || model.scan.isLoadingExtras || model.scan.isScanTaskRunning {
            try? await Task.sleep(for: .milliseconds(200))
        }
        switch environment["DEVSWEEP_SNAPSHOT_SCREEN"] {
        case "blocks": model.chartStyle = .blocks
        case "runtimes": model.screen = .simulatorRuntimes
        case "remove-runtime":
            // Shows the sheet only; nothing here presses Remove.
            model.screen = .simulatorRuntimes
        case "xcodes": model.screen = .xcodeVersions
        case "scanning": model.rewindScan(toMeasured: 5)
        case "cleaned", "putback":
            // The confirmed step directly: never the quit prompt, which would
            // ask the real Xcode to quit.
            await model.cleaning.confirmClean(CleaningModel.PendingClean(
                items: model.marks.markedRows.map(\.item),
                stage: .confirm))
            model.cleaning.dismissNotice()
            if environment["DEVSWEEP_SNAPSHOT_SCREEN"] == "putback" {
                await model.cleaning.putBack(.swiftpmCache)
                model.selection = .swiftpmCache
            }
        default: break
        }
        if let id = environment["DEVSWEEP_SNAPSHOT_SELECT"], !id.isEmpty {
            model.select(snapshotID: id)
        }
        if environment["DEVSWEEP_SNAPSHOT_SCREEN"] == "remove-runtime" {
            model.runtimeToRemove = model.currentRuntime
        }
        try? await Task.sleep(for: .milliseconds(600))

        let width = environment["DEVSWEEP_SNAPSHOT_WIDTH"].flatMap(Double.init) ?? 1280
        // `about` and `menubar` draw the About window's content and the menu
        // bar item's panel instead of the main window.
        let content = switch environment["DEVSWEEP_SNAPSHOT_SCREEN"] {
        case "about": AnyView(AboutView().background(Color(nsColor: .windowBackgroundColor)))
        case "menubar": AnyView(MenuBarPanel().background(.regularMaterial))
        default: AnyView(SnapshotLayout(width: width))
        }
        let renderer = ImageRenderer(content: content
            .environment(models: model)
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        if let image = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
        }
        // Not terminate(_:), which waits on an open sheet.
        exit(0)
    }
}

/// The window's three columns, drawn without the views AppKit backs.
private struct SnapshotLayout: View {
    @Environment(AppModel.self) private var model
    @Environment(ScanModel.self) private var scan
    let width: CGFloat

    var body: some View {
        let showsInspector = self.width >= WindowLayout.sidebar.ideal + WindowLayout.dividers + WindowLayout
            .inspectorShowFrom
        HStack(spacing: 0) {
            SnapshotSidebar()
                .frame(width: 232)
                .background(.fill.quaternary)
            Divider()
            VStack(spacing: 0) {
                SnapshotHeader()
                switch self.model.screen {
                case .overview:
                    OverviewContent()
                    Spacer(minLength: 0)
                    OverviewFooter()
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                case .simulatorRuntimes:
                    RuntimesContent()
                    Spacer(minLength: 0)
                case .xcodeVersions:
                    XcodesContent()
                    Spacer(minLength: 0)
                case .worktrees:
                    WorktreesContent()
                    Spacer(minLength: 0)
                case .androidStudios, .androidSDK, .gradleCaches:
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity)
            if showsInspector {
                Divider()
                self.inspector
            }
        }
        .frame(width: self.width, height: 860)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if let runtime = model.runtimeToRemove {
                ZStack {
                    Color.black.opacity(0.35)
                    RemoveRuntimeSheet(runtime: runtime)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                        .shadow(radius: 20)
                }
            }
        }
    }

    private var inspector: some View {
        Group {
            switch self.model.screen {
            case .overview:
                if let item = model.selection, let row = scan.rows[item] {
                    VStack(spacing: 0) {
                        ItemDetails(row: row)
                        Spacer(minLength: 0)
                        InspectorAction(row: row).padding(18)
                    }
                }
            case .simulatorRuntimes: RuntimeInspector()
            case .xcodeVersions: XcodeInspector()
            case .androidStudios, .androidSDK, .gradleCaches: AndroidInspector()
            case .worktrees: WorktreeInspector()
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.fill.quinary)
    }
}

private struct SnapshotHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(self.model.screen == .overview ? "Overview" : self.model
                    .screen == .xcodeVersions ? "Xcode versions" : "Simulator runtimes")
                    .font(.title2.weight(.semibold))
                Text(self.model.subtitle).font(.callout).foregroundStyle(.muted)
            }
            Spacer()
            if self.model.screen == .overview {
                HStack(spacing: 0) {
                    ForEach(AppModel.ChartStyle.allCases) { style in
                        Text(style.rawValue)
                            .font(.callout.weight(style == self.model.chartStyle ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                style == self.model.chartStyle ? Color.primary.opacity(0.14) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(2)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
            }
            Text("Scan Again")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.fill.tertiary, in: Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }
}

private struct SnapshotSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(ScanModel.self) private var scan

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            self.row(highlighted: self.model.screen == .overview) {
                Label("Overview", systemImage: "chart.pie").fontWeight(.medium)
            }
            self.heading("Caches")
            ForEach(Family.allCases) { family in
                self.row {
                    Dot(color: Palette.color(family))
                    Text(family.name)
                    Spacer()
                    Text(self.scan.tally.measuredKilobytes(of: family).map { SizeText.of(kilobytes: $0) } ?? "–")
                        .foregroundStyle(.muted).monospacedDigit()
                }
            }
            self.heading("Also worth a look")
            self.row(highlighted: self.model.screen == .xcodeVersions) {
                Text("Xcode versions")
                Spacer()
                Text((self.scan.extras?.xcodesKilobytes).map { SizeText.of(kilobytes: $0) } ?? "–")
                    .foregroundStyle(.muted)
                    .monospacedDigit()
            }
            self.row(highlighted: self.model.screen == .simulatorRuntimes) {
                Text("Simulator runtimes")
                Spacer()
                Text((self.scan.extras?.runtimesKilobytes).map { SizeText.of(kilobytes: $0) } ?? "–")
                    .foregroundStyle(.muted)
                    .monospacedDigit()
            }
            Spacer()
            DiskMeter().padding(.horizontal, 6)
        }
        .padding(.horizontal, 10)
        .padding(.top, 44)
        .padding(.bottom, 16)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.muted).padding(.horizontal, 10).padding(.top, 16)
            .padding(
                .bottom,
                4)
    }

    private func row(highlighted: Bool = false, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 9) { content() }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(highlighted ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
    }
}

extension AppModel {
    /// Selects an item, an Xcode by its folder's name, or a runtime by id,
    /// for snapshots.
    func select(snapshotID id: String) {
        if let item = Item(rawValue: id) {
            selection = item
        } else if let xcode = self.scan.extras?.xcodes.first(where: { ($0.path as NSString).lastPathComponent == id }) {
            selectedXcode = xcode.path
        } else if let worktree = self.scan.extras?.worktrees.first(where: { $0.name == id }) {
            selectedWorktree = worktree.path
        } else {
            selectedRuntime = id
        }
    }
}
#endif
