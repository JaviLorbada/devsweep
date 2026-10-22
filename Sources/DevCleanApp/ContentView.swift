import AppKit
import DevCleanKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    /// Whether you want the inspector; it shows when the center also has room.
    @State private var wantsInspector = true
    @State private var inspectorHasRoom = true

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: WindowLayout.sidebar.min, ideal: WindowLayout.sidebar.ideal, max: WindowLayout.sidebar.max
                )
        } detail: {
            // The inspector is a column inside the detail area, not SwiftUI's
            // inspector: showing or hiding that one resizes the window, and with
            // the window also resizing on its own the two fed each other until
            // AppKit gave up mid-layout.
            HStack(spacing: WindowLayout.gap) {
                Group {
                    switch model.screen {
                    case .overview: OverviewView()
                    case .xcodeVersions: XcodeVersionsView()
                    case .simulatorRuntimes: SimulatorRuntimesView()
                    }
                }
                .frame(minWidth: WindowLayout.centerMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
                .panel()
                if wantsInspector && inspectorHasRoom {
                    Group {
                        switch model.screen {
                        case .overview: ItemInspector()
                        case .xcodeVersions: XcodeInspector()
                        case .simulatorRuntimes: RuntimeInspector()
                        }
                    }
                    .frame(width: WindowLayout.inspectorWidth)
                    .frame(maxHeight: .infinity)
                    .panel()
                    .transition(.move(edge: .trailing))
                }
            }
            .padding([.horizontal, .bottom], WindowLayout.gap)
            .background(Palette.backdrop)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                updateInspectorRoom(forDetailWidth: width)
            }
            #if DEBUG
            .onChange(of: wantsInspector && inspectorHasRoom, initial: true) { _, shown in model.debugInspectorShown = shown }
            #endif
            .navigationTitle(title)
            .navigationSubtitle(model.subtitle)
            .toolbar { toolbar }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .alert(
            pendingTitle,
            isPresented: Binding(get: { model.pendingClean != nil }, set: { if !$0 { model.pendingClean = nil } }),
            presenting: model.pendingClean
        ) { pending in
            switch pending.stage {
            case .quitApps:
                Button("Quit and Clean") { Task { await model.quitAppsAndClean(pending) } }
                if pending.items.contains(where: { !$0.needsXcodeClosed }) {
                    Button("Clean the Others") { model.cleanSkippingXcodeItems(pending) }
                }
                Button("Cancel", role: .cancel) {}
            case .confirm:
                Button(model.moveToTrash ? "Clean" : "Delete", role: model.moveToTrash ? nil : .destructive) {
                    Task { await model.confirmClean(pending) }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: { pending in
            Text(CleanPrompt.message(for: pending, moveToTrash: model.moveToTrash))
        }
        .sheet(item: $model.runtimeToRemove) { runtime in
            RemoveRuntimeSheet(runtime: runtime)
                .environment(model)
        }
        .alert(
            model.notice?.title ?? "",
            isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }),
            presenting: model.notice
        ) { _ in
            Button("OK") {}
        } message: { notice in
            Text(notice.message)
        }
        .task {
            #if DEBUG
            if DebugLaunch.isRequested { FileHandle.standardError.write(Data("debug launch: window appeared\n".utf8)) }
            #endif
            model.scan()
            #if DEBUG
            await Snapshotter.runIfAsked(model)
            await DebugLaunch.run(model)
            #endif
        }
    }

    /// Hides the inspector when the detail area can't hold the center at its
    /// minimum next to it, the way Mail collapses a pane, and brings it back
    /// with some room to spare. The detail area's width doesn't depend on
    /// whether the inspector shows, so this can't feed back on itself, and
    /// it is set right away: no AppKit column collapses.
    private func updateInspectorRoom(forDetailWidth width: CGFloat) {
        let hasRoom = inspectorHasRoom
            ? width >= WindowLayout.inspectorHideBelow
            : width >= WindowLayout.inspectorShowFrom
        guard hasRoom != inspectorHasRoom else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { inspectorHasRoom = hasRoom }
    }

    private var pendingTitle: String {
        guard let pending = model.pendingClean else { return "" }
        let size = SizeText.of(kilobytes: pending.items.compactMap { model.rows[$0]?.kilobytes }.reduce(0, +))
        return CleanPrompt.title(for: pending, size: size, moveToTrash: model.moveToTrash)
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
                if wantsInspector && !inspectorHasRoom {
                    // Asked for while hidden for room: make room.
                    WindowSizing.widen(to: WindowLayout.sidebar.ideal + WindowLayout.inspectorShowFrom + 10)
                } else {
                    wantsInspector.toggle()
                }
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
            Text(capsuleText)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)
            ProgressView(value: model.scanProgress)
                .progressViewStyle(.linear)
                .frame(width: 64)
                .animation(.easeInOut(duration: 0.3), value: model.scanProgress)
        }
        .padding(.horizontal, 6)
    }
}

/// Resizes the main window.
enum WindowSizing {
    /// Makes the key window at least `width` wide, growing to the right as far
    /// as the screen allows and then to the left.
    @MainActor
    static func widen(to width: CGFloat) {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first(where: \.isVisible),
              window.frame.width < width else { return }
        var frame = window.frame
        frame.size.width = width
        if let visible = window.screen?.visibleFrame {
            frame.size.width = min(frame.width, visible.width)
            if frame.maxX > visible.maxX { frame.origin.x = max(visible.minX, visible.maxX - frame.width) }
        }
        window.setFrame(frame, display: true, animate: true)
    }
}

extension ScanCapsule {
    /// "Measuring DerivedData", "Measuring DerivedData and 2 more".
    var capsuleText: String {
        let measuring = model.measuringItems
        guard let first = measuring.last else { return "Listing Xcodes and runtimes" }
        return measuring.count == 1 ? "Measuring \(first.shortName)" : "Measuring \(first.shortName) and \(measuring.count - 1) more"
    }
}

/// One of the window's columns as a rounded panel on the darker backdrop.
struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: WindowLayout.panelCornerRadius, style: .continuous)
        content
            .background(Palette.panel, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.separator.opacity(0.5)))
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
    func panel() -> some View { modifier(PanelModifier()) }
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
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
    }
}
