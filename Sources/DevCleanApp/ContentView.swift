import DevCleanKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showsInspector = true

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(232)
        } detail: {
            Group {
                switch model.screen {
                case .overview: OverviewView()
                case .xcodeVersions: XcodeVersionsView()
                case .simulatorRuntimes: SimulatorRuntimesView()
                }
            }
            .navigationTitle(title)
            .navigationSubtitle(model.statusLine)
            .toolbar { toolbar }
        }
        .inspector(isPresented: $showsInspector) {
            Group {
                switch model.screen {
                case .overview: ItemInspector()
                case .xcodeVersions: XcodeInspector()
                case .simulatorRuntimes: RuntimeInspector()
                }
            }
            .inspectorColumnWidth(300)
        }
        .task {
            model.scan()
            #if DEBUG
            await Snapshotter.runIfAsked(model)
            #endif
        }
    }

    private var title: String {
        switch model.screen {
        case .overview: "Overview"
        case .xcodeVersions: "Xcode versions"
        case .simulatorRuntimes: "Simulator runtimes"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var model = model
        if model.isScanning {
            ToolbarItem {
                ScanCapsule()
            }
        }
        if model.screen == .overview {
            ToolbarItem {
                Picker("Chart", selection: $model.chartStyle) {
                    ForEach(AppModel.ChartStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Show sizes as a ring or as blocks")
            }
        }
        ToolbarItem {
            Button(model.isScanning ? "Stop" : "Scan Again") {
                model.isScanning ? model.stopScan() : model.scan()
            }
            .disabled(model.engine == nil)
        }
        ToolbarItem {
            Button("Inspector", systemImage: "sidebar.trailing") {
                showsInspector.toggle()
            }
            .help("Show or hide the inspector")
        }
    }
}

/// "Measuring DerivedData" with a thin bar for how many items are done.
struct ScanCapsule: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Text(model.currentItem.map { "Measuring \($0.shortName)" } ?? "Listing Xcodes and runtimes")
                .font(.callout)
                .lineLimit(1)
            ProgressView(value: model.scanProgress)
                .progressViewStyle(.linear)
                .frame(width: 96)
                .animation(.easeInOut(duration: 0.3), value: model.scanProgress)
        }
        .padding(.horizontal, 6)
        .fixedSize()
    }
}

/// A rounded panel on the window background, for charts and lists.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.6)))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

/// The small upper-case headings used in the inspector.
struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.4)
            .foregroundStyle(.secondary)
    }
}

/// A thin proportional bar on a faint track.
struct ThinBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.primary.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, min(1, fraction)) * proxy.size.width)
                }
        }
        .frame(height: height)
    }
}

/// A colored dot standing for an item or family.
struct Dot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// A small tinted label such as "project gone" or "selected".
struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
    }
}
