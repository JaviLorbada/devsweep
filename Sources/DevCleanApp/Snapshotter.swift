#if DEBUG
import AppKit
import DevCleanKit
import SwiftUI

/// Development aid: with `DEVCLEAN_SNAPSHOT=/path/file.png` set, waits for the
/// scan to finish, draws the window's content into that file and quits.
/// `DEVCLEAN_SNAPSHOT_SCREEN` picks `overview`, `scanning`, `blocks`, `runtimes`,
/// `xcodes`, `cleaned` (cleans what is marked first) or `putback` (then puts
/// the SwiftPM cache back). Cleaning must only ever run against a fake home,
/// with `DEVCLEAN_TRASH_FOLDER` set;
/// `DEVCLEAN_SNAPSHOT_APPEARANCE` picks `dark` or `light`;
/// `DEVCLEAN_SNAPSHOT_SELECT` picks an item id or runtime id to select.
///
/// The window itself can't be captured without screen recording permission,
/// so this draws the same content views with ImageRenderer, laid out like the
/// window. System controls that AppKit draws come out as placeholders.
enum Snapshotter {
    @MainActor
    static func runIfAsked(_ model: AppModel) async {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["DEVCLEAN_SNAPSHOT"] else { return }
        let dark = environment["DEVCLEAN_SNAPSHOT_APPEARANCE"] != "light"
        NSApplication.shared.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        while model.isScanning || model.isLoadingExtras {
            try? await Task.sleep(for: .milliseconds(200))
        }
        switch environment["DEVCLEAN_SNAPSHOT_SCREEN"] {
        case "blocks": model.chartStyle = .blocks
        case "runtimes": model.screen = .simulatorRuntimes
        case "xcodes": model.screen = .xcodeVersions
        case "scanning": model.rewindScan(toMeasured: 5)
        case "cleaned", "putback":
            // The confirmed step directly: never the quit prompt, which would
            // ask the real Xcode to quit.
            await model.confirmClean(AppModel.PendingClean(items: model.markedRows.map(\.item), stage: .confirm))
            model.notice = nil
            if environment["DEVCLEAN_SNAPSHOT_SCREEN"] == "putback" {
                await model.putBack(.swiftpmCache)
                model.selection = .swiftpmCache
            }
        default: break
        }
        if let id = environment["DEVCLEAN_SNAPSHOT_SELECT"], !id.isEmpty {
            model.select(snapshotID: id)
        }
        try? await Task.sleep(for: .milliseconds(600))

        let renderer = ImageRenderer(content: SnapshotLayout()
            .environment(model)
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        if let image = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
        }
        NSApplication.shared.terminate(nil)
    }
}

/// The window's three columns, drawn without the views AppKit backs.
private struct SnapshotLayout: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            SnapshotSidebar()
                .frame(width: 232)
                .background(.fill.quaternary)
            Divider()
            VStack(spacing: 0) {
                SnapshotHeader()
                switch model.screen {
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
                }
            }
            .frame(maxWidth: .infinity)
            Divider()
            Group {
                switch model.screen {
                case .overview:
                    if let item = model.selection, let row = model.rows[item] {
                        VStack(spacing: 0) {
                            ItemDetails(row: row)
                            Spacer(minLength: 0)
                            InspectorAction(row: row).padding(18)
                        }
                    }
                case .simulatorRuntimes: RuntimeInspector()
                case .xcodeVersions: XcodeInspector()
                }
            }
            .frame(width: 300)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.fill.quinary)
        }
        .frame(width: 1280, height: 860)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SnapshotHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.screen == .overview ? "Overview" : model.screen == .xcodeVersions ? "Xcode versions" : "Simulator runtimes")
                    .font(.title2.weight(.semibold))
                Text(model.statusLine).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if model.screen == .overview {
                HStack(spacing: 0) {
                    ForEach(AppModel.ChartStyle.allCases) { style in
                        Text(style.rawValue)
                            .font(.callout.weight(style == model.chartStyle ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(style == model.chartStyle ? Color.primary.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row(highlighted: model.screen == .overview) {
                Label("Overview", systemImage: "chart.pie").fontWeight(.medium)
            }
            heading("Caches")
            ForEach(Family.allCases) { family in
                row {
                    Dot(color: Palette.color(family))
                    Text(family.name)
                    Spacer()
                    Text(model.measuredKilobytes(of: family).map { SizeText.of(kilobytes: $0) } ?? "–")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            heading("Also worth a look")
            row(highlighted: model.screen == .xcodeVersions) {
                Text("Xcode versions")
                Spacer()
                Text(model.xcodesKilobytes.map { SizeText.of(kilobytes: $0) } ?? "–").foregroundStyle(.secondary).monospacedDigit()
            }
            row(highlighted: model.screen == .simulatorRuntimes) {
                Text("Simulator runtimes")
                Spacer()
                Text(model.runtimesKilobytes.map { SizeText.of(kilobytes: $0) } ?? "–").foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            DiskMeter().padding(.horizontal, 6)
        }
        .padding(.horizontal, 10)
        .padding(.top, 44)
        .padding(.bottom, 16)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 4)
    }

    private func row<Content: View>(highlighted: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 9) { content() }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(highlighted ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
    }
}

extension AppModel {
    /// Selects an item or a runtime by id, for snapshots.
    func select(snapshotID id: String) {
        if let item = Item(rawValue: id) {
            selection = item
        } else {
            selectedRuntime = id
        }
    }
}
#endif
