import AppKit
import DevSweepKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The window's width, which caps the sidebar's.
    @State private var windowWidth: CGFloat?
    /// Whether the sidebar is hidden, leaving the window's controls over the
    /// center header. Read from where the detail area starts, not bound to
    /// the split view: a binding's starting value overrode the hidden sidebar
    /// AppKit restores at launch, and showing it widened the window.
    @State private var sidebarHidden = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: WindowLayout.sidebar.min,
                    ideal: WindowLayout.sidebar.ideal,
                    max: self.windowWidth.map(WindowLayout.sidebarMaximum(forWindowWidth:)) ?? WindowLayout.sidebar.max)
        } detail: {
            // The inspector is a column inside the detail area, not SwiftUI's
            // inspector: showing or hiding that one resizes the window, and with
            // the window also resizing on its own the two fed each other until
            // AppKit gave up mid-layout.
            HStack(spacing: WindowLayout.gap) {
                // The header is a bar over the screen's scroll view: content
                // scrolls under it, softened by the scroll edge effect.
                Group {
                    switch model.screen {
                    case .overview: OverviewView()
                    case .xcodeVersions: XcodeVersionsView()
                    case .simulatorRuntimes: SimulatorRuntimesView()
                    case .androidStudios: AndroidStudiosView()
                    case .androidSDK: AndroidSDKView()
                    case .gradleCaches: GradleCachesView()
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .safeAreaBar(edge: .top) {
                    CenterHeader(title: self.title, sidebarHidden: self.sidebarHidden)
                }
                .frame(minWidth: WindowLayout.centerMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
                .panel()
                if model.inspectorPlacement == .docked {
                    self.inspector
                        .frame(width: WindowLayout.inspectorWidth)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .topTrailing) {
                            // On the window's controls' line, with the center
                            // header's row, and the inspector's own margin.
                            InspectorToggle()
                                .frame(height: CenterHeader.rowHeight)
                                .padding(.trailing, 18)
                        }
                        .panel()
                        .transition(InspectorMotion.transition(reduceMotion: self.reduceMotion))
                }
            }
            // Too narrow to sit beside the center, the inspector floats over
            // its trailing side, below the header and above the overview's
            // footer, so their controls stay in reach. Its toggle stays in the
            // header.
            .overlay(alignment: .topTrailing) {
                if model.inspectorPlacement == .floating {
                    self.inspector
                        .frame(width: WindowLayout.inspectorWidth)
                        .frame(maxHeight: .infinity)
                        .panel()
                        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                        .padding(.top, CenterHeader.height)
                        .padding(
                            .bottom,
                            (model.screen == .overview ? model.overviewFooterHeight : 0) + WindowLayout.gap)
                        .padding(.trailing, WindowLayout.gap)
                        .transition(InspectorMotion.transition(reduceMotion: self.reduceMotion))
                }
            }
            // With the sidebar shown, the detail area starts past it; hidden,
            // a gap from the window's edge.
            .onGeometryChange(for: Bool.self) { $0.frame(in: .global).minX < WindowLayout.sidebar.min } action: {
                self.sidebarHidden = $0
            }
            // Only showing or hiding it by choice moves anything; when the
            // window gets too narrow for it beside the center, it floats at once.
            .animation(InspectorMotion.layoutAnimation(reduceMotion: self.reduceMotion), value: model.wantsInspector)
            // No title bar strip above the panels: they start at the window's
            // top, level with the sidebar, the traffic lights in its corner.
            .padding(WindowLayout.gap)
            .background(Palette.backdrop)
            .ignoresSafeArea(.container, edges: .top)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                self.updateInspectorRoom(forDetailWidth: width)
            }
            .navigationTitle(self.title)
            .navigationSubtitle(model.subtitle)
            // The title and status are in the center panel's header, and
            // the inspector's toggle in its panel's corner or that header.
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        // The window's own width, from AppKit: SwiftUI's geometry here is the
        // split view's, which grows past the window when the sidebar is too
        // wide, and would keep the sidebar as wide as it is.
        .background(WindowWidthReader { self.windowWidth = $0 })
        .alert(
            self.pendingTitle,
            isPresented: Binding(get: { model.pendingClean != nil }, set: { if !$0 { model.pendingClean = nil } }),
            presenting: model.pendingClean)
        { pending in
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
            presenting: model.notice)
        { _ in
            Button("OK") {}
        } message: { notice in
            Text(notice.message)
        }
        #if DEBUG
        .transformEnvironment(\.appearsActive) { if DebugLaunch.drawsActive { $0 = true } }
        #endif
        .task {
            #if DEBUG
            if DebugLaunch.isRequested { FileHandle.standardError.write(Data("debug launch: window appeared\n".utf8)) }
            #endif
            if model.preferences.scanOnLaunch { model.scan() }
            #if DEBUG
            await Snapshotter.runIfAsked(model)
            await DebugLaunch.run(model)
            #endif
        }
    }

    /// Floats the inspector over the center when the detail area can't hold
    /// the center at its minimum beside it, and docks it again with some
    /// room to spare. The detail area's width doesn't depend on where the
    /// inspector is, so this can't feed back on itself, and it is set right
    /// away: no AppKit column collapses.
    private func updateInspectorRoom(forDetailWidth width: CGFloat) {
        let hasRoom = self.model.inspectorHasRoom
            ? width >= WindowLayout.inspectorHideBelow
            : width >= WindowLayout.inspectorShowFrom
        guard hasRoom != self.model.inspectorHasRoom else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { self.model.inspectorHasRoom = hasRoom }
    }

    /// The inspector for the screen showing, docked or floating.
    @ViewBuilder
    private var inspector: some View {
        switch self.model.screen {
        case .overview: ItemInspector()
        case .xcodeVersions: XcodeInspector()
        case .simulatorRuntimes: RuntimeInspector()
        case .androidStudios, .androidSDK, .gradleCaches: AndroidInspector()
        }
    }

    private var pendingTitle: String {
        guard let pending = model.pendingClean else { return "" }
        let size = SizeText.of(kilobytes: pending.items.compactMap { self.model.rows[$0]?.kilobytes }.reduce(0, +))
        return CleanPrompt.title(for: pending, size: size, moveToTrash: self.model.moveToTrash)
    }

    private var title: String {
        switch self.model.screen {
        case .overview: "Overview"
        case .xcodeVersions: "Xcode versions"
        case .simulatorRuntimes: "Simulator runtimes"
        case .androidStudios: "Android Studio versions"
        case .androidSDK: "SDK and emulators"
        case .gradleCaches: "Gradle caches"
        }
    }
}

/// How the inspector comes and goes when it is shown or hidden: it slides in
/// from the trailing edge as the center narrows, with the sidebar's timing.
/// That is AppKit's split view collapsing its sidebar, measured: ease in and
/// out over a quarter of a second. With Reduce Motion it fades in place
/// instead, and the center takes its new width at once.
enum InspectorMotion {
    static let duration = 0.25
    static let animation = Animation.easeInOut(duration: duration)

    /// The animation for the center's change of width, none with Reduce Motion.
    static func layoutAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : self.animation
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity.animation(self.animation) : .move(edge: .trailing)
    }
}

/// Reports the width of the window it sits in, now and whenever it resizes.
struct WindowWidthReader: NSViewRepresentable {
    let onChange: @MainActor (CGFloat) -> Void

    func makeNSView(context: Context) -> ReaderView {
        ReaderView(onChange: self.onChange)
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = self.onChange
    }

    final class ReaderView: NSView {
        var onChange: @MainActor (CGFloat) -> Void
        private var observation: (any NSObjectProtocol)?

        init(onChange: @escaping @MainActor (CGFloat) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observation { NotificationCenter.default.removeObserver(observation) }
            observation = nil
            guard let window else { return }
            self.observation = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main)
            { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
            self.report()
        }

        private func report() {
            if let width = window?.frame.width { self.onChange(width) }
        }
    }
}

/// One of the window's columns as a rounded panel on the darker backdrop.
///
/// The corners follow the window's, as the sidebar's do: concentric with the
/// window's corner where a panel meets it, and the sidebar's radius elsewhere.
struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = ConcentricRectangle(
            corners: .concentric(minimum: .fixed(WindowLayout.panelCornerRadius)),
            isUniform: false)
        // The shape can't be inset, so the border is a stroke twice as wide
        // with its outer half clipped off.
        content
            .background(Palette.panel, in: shape)
            .overlay(shape.stroke(.separator.opacity(0.5), lineWidth: 2))
            .clipShape(shape)
    }
}

/// A table row's selection as macOS draws it: the whole row, edge to edge, in
/// the selection color while the window is active and gray when it is not,
/// with text that turns light on the color.
struct TableRowSelection: ViewModifier {
    @Environment(\.appearsActive) private var appearsActive
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.backgroundProminence, self.selected && self.appearsActive ? .increased : .standard)
            .background {
                if self.selected {
                    Rectangle()
                        .fill(Color(nsColor: self
                                .appearsActive ? .selectedContentBackgroundColor :
                                .unemphasizedSelectedContentBackgroundColor))
                }
            }
    }
}

/// A button in a table row. On the selection color its usual bezel is a
/// translucent tint of the blue, and neither dark nor light text reaches
/// 4.5:1 on it; dark glass with white text there reads at over 10:1.
struct RowControlModifier: ViewModifier {
    @Environment(\.backgroundProminence) private var prominence

    func body(content: Content) -> some View {
        if self.prominence == .increased {
            content.buttonStyle(.glass).environment(\.colorScheme, .dark)
        } else {
            content
        }
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
    func tableRowSelection(_ selected: Bool) -> some View { modifier(TableRowSelection(selected: selected)) }
    func rowControl() -> some View { modifier(RowControlModifier()) }
}

/// The small upper-case headings used in the inspector.
struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(self.text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.4)
            .foregroundStyle(.muted)
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
                        .fill(self.color)
                        .frame(width: max(0, min(1, self.fraction)) * proxy.size.width)
                }
        }
        .frame(height: self.height)
    }
}

/// A colored dot standing for an item or family.
struct Dot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(self.color).frame(width: self.size, height: self.size)
    }
}

/// A small tinted label such as "project gone" or "selected".
///
/// The text is a darker shade of the color in light mode and a lighter one
/// in dark mode: the color itself on its tint is about 2:1 for orange and
/// 3:1 for blue. On a selected row it turns white on a darker patch of the
/// selection color: a light patch, or the tint, would drop it below 4.5:1.
struct Badge: View {
    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let color: Color

    var body: some View {
        let onSelection = self.prominence == .increased
        let dark = self.colorScheme == .dark
        let textColor = self.color.mix(with: dark ? .white : .black, by: dark ? 0.35 : 0.45, in: .device)
        Text(self.text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(onSelection ? .white : textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                onSelection ? Color.black.opacity(0.2) : self.color.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 4))
    }
}
