import SwiftUI

/// The center panel's top: a row with the screen's title on the left and, on
/// the right, what acts on the scan, its progress, Ring or Blocks, and Scan
/// Again or Stop, then the inspector's toggle unless the inspector is docked;
/// and the status under it, across the panel. The row is centered on the
/// window's controls' line, as the traffic lights and the sidebar's toggle
/// are, so they read as one row whether the sidebar shows or not.
///
/// Sized from the width it is given, like the footer, so the controls drop
/// their words instead of asking the column for more room.
struct CenterHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    /// Whether the sidebar is hidden, leaving the window's own controls over
    /// the header's leading corner.
    var sidebarHidden = false

    /// The space on each side of the row.
    static let horizontalPadding: CGFloat = 22

    /// Extra room on the leading side for the window's controls, while the
    /// sidebar is hidden and the center panel starts a gap from the window's
    /// edge.
    static let insetWithoutSidebar = WindowLayout.windowControlsEnd - WindowLayout.gap - horizontalPadding

    static let height: CGFloat = 56
    /// The row's height, which puts its middle on the window's controls'
    /// line: the panel starts a gap below the window's top edge.
    static let rowHeight = 2 * (WindowLayout.windowControlsLine - WindowLayout.gap)

    /// What the controls show at a given width of the center panel.
    struct Fit: Equatable {
        /// "Measuring DerivedData" next to the progress bar.
        var capsuleText: Bool
        /// "Ring" and "Blocks" rather than their icons.
        var pickerText: Bool

        init(width: CGFloat) {
            self.capsuleText = width >= 680
            self.pickerText = width >= 560
        }
    }

    var body: some View {
        let inset = self.sidebarHidden ? Self.insetWithoutSidebar : 0
        GeometryReader { proxy in
            // The controls drop their words by the width left after the inset.
            self.row(fit: Fit(width: proxy.size.width - inset), inset: inset)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: Self.height)
        .animation(self.reduceMotion ? nil : InspectorMotion.animation, value: self.sidebarHidden)
    }

    private func row(fit: Fit, inset: CGFloat) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(self.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        if model.isScanning {
                            // With the container's default transition, the capsule
                            // appearing when a scan starts stayed invisible and took
                            // no room.
                            ScanCapsule(showsText: fit.capsuleText)
                                .glassEffectTransition(.identity)
                        }
                        if model.screen == .overview {
                            ChartStylePicker(selection: $model.chartStyle, showsText: fit.pickerText)
                        }
                        Button(model.isScanning ? "Stop" : "Scan Again") {
                            model.isScanning ? model.stopScan() : model.scan()
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .disabled(model.engine == nil)
                        if model.inspectorPlacement != .docked {
                            InspectorToggle()
                        }
                    }
                }
                .fixedSize()
            }
            .frame(height: Self.rowHeight)
            Text(model.subtitle)
                .font(.callout)
                .foregroundStyle(.muted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.leading, Self.horizontalPadding + inset)
        .padding(.trailing, Self.horizontalPadding)
    }
}

/// Shows or hides the inspector. It sits in the inspector's top-right corner
/// while the inspector is docked, and in the center panel's header, after
/// Scan Again, while it floats or is hidden. The window has no toolbar strip
/// to put it in.
struct InspectorToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let title = AppCommands.inspectorTitle(shown: self.model.inspectorShown)
        Button(title, systemImage: "sidebar.trailing") { self.model.toggleInspector() }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .help(title)
    }
}

/// "Measuring DerivedData" with a thin bar for how many items are done.
struct ScanCapsule: View {
    @Environment(AppModel.self) private var model
    var showsText = true

    var body: some View {
        HStack(spacing: 10) {
            if self.showsText {
                Text(self.capsuleText)
                    .font(.callout)
                    .foregroundStyle(.muted)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .leading)
            }
            ProgressView(value: self.model.scanProgress)
                .progressViewStyle(.linear)
                .frame(width: 64)
                .animation(Motion.animation(.easeInOut(duration: 0.3)), value: self.model.scanProgress)
        }
        .padding(.horizontal, 14)
        .frame(height: ChartStylePicker.height)
        .glassEffect(.regular, in: .capsule)
        .help(self.capsuleText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.capsuleText)
        .accessibilityValue("\(Int(self.model.scanProgress * 100)) percent")
    }

    /// "Measuring DerivedData", "Measuring DerivedData and 2 more".
    var capsuleText: String {
        let measuring = self.model.measuringItems
        guard let first = measuring.last else { return "Listing Xcodes and runtimes" }
        return measuring.count == 1 ? "Measuring \(first.shortName)" : "Measuring \(first.shortName) and "
            + "\(measuring.count - 1) more"
    }
}

/// Ring or Blocks as a glass track with a glass thumb under the chosen one,
/// the way macOS 26 draws a segmented control in a toolbar; outside one, the
/// system control has no glass. Click a segment to choose it, or drag the
/// thumb and let go nearer the other.
struct ChartStylePicker: View {
    @Binding var selection: AppModel.ChartStyle
    var showsText = true
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Each segment's frame in the track, where the thumb goes.
    @State private var segmentFrames: [AppModel.ChartStyle: CGRect] = [:]
    /// Where the thumb's center is while it is dragged.
    @State private var dragX: CGFloat?

    static let height: CGFloat = 32
    private nonisolated static let track = "chart style track"

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                ForEach(AppModel.ChartStyle.allCases) { style in
                    self.segment(style, selected: style == self.selection)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.track)) } action: { frame in
                            self.segmentFrames[style] = frame
                        }
                }
            }
            .coordinateSpace(.named(Self.track))
            .background(alignment: .topLeading) { self.thumb }
            .highPriorityGesture(self.drag)
            .padding(3)
            .frame(height: Self.height)
            .glassEffect(.regular, in: .capsule)
        }
        .help("Show sizes as a ring or as blocks")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart")
    }

    private func segment(_ style: AppModel.ChartStyle, selected: Bool) -> some View {
        Button {
            withAnimation(self.reduceMotion ? nil : .snappy(duration: 0.25)) { self.selection = style }
        } label: {
            Group {
                if self.showsText {
                    Text(style.rawValue)
                } else {
                    Image(systemName: style.systemImage)
                }
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.muted))
            .padding(.horizontal, self.showsText ? 14 : 10)
            .frame(maxHeight: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Under the chosen segment, or under the pointer while dragged.
    @ViewBuilder
    private var thumb: some View {
        if let frame = self.thumbFrame {
            Color.clear
                .frame(width: frame.width, height: frame.height)
                .glassEffect(.regular.tint(Palette.raisedSegment.opacity(0.8)).interactive(), in: .capsule)
                .glassEffectID("thumb", in: self.glass)
                .offset(x: frame.minX, y: frame.minY)
                .accessibilityHidden(true)
        }
    }

    private var thumbFrame: CGRect? {
        guard var frame = self.segmentFrames[self.selection] else { return nil }
        if let dragX, let nearest = self.nearest(to: dragX), let width = self.segmentFrames[nearest]?.width {
            let frames = self.segmentFrames.values
            let leading = frames.map(\.minX).min() ?? 0
            let trailing = frames.map(\.maxX).max() ?? 0
            frame.size.width = width
            frame.origin.x = min(max(dragX - width / 2, leading), trailing - width)
        }
        return frame
    }

    /// The segment whose middle is closest to `x`.
    private func nearest(to x: CGFloat) -> AppModel.ChartStyle? {
        self.segmentFrames.min { abs($0.value.midX - x) < abs($1.value.midX - x) }?.key
    }

    /// Moves the thumb with the pointer, then settles it on the nearest segment.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.track))
            .onChanged { value in self.dragX = value.location.x }
            .onEnded { value in
                let chosen = self.nearest(to: value.location.x) ?? self.selection
                withAnimation(self.reduceMotion ? nil : .snappy(duration: 0.25)) {
                    self.selection = chosen
                    self.dragX = nil
                }
            }
    }
}

extension AppModel.ChartStyle {
    var systemImage: String {
        switch self {
        case .ring: "chart.pie"
        case .blocks: "square.grid.2x2"
        }
    }
}
