import CoreGraphics
import Observation

/// The window's own state: the screen on show, Ring or Blocks, and whether
/// and where the inspector shows.
@MainActor
@Observable
final class WindowViewModel: Navigation {
    enum Screen: Hashable {
        case overview
        case xcodeVersions
        case simulatorRuntimes
        case androidStudios
        case androidSDK
        case gradleCaches
        case worktrees
    }

    enum ChartStyle: String, CaseIterable, Identifiable {
        case ring = "Ring"
        case blocks = "Blocks"
        var id: Self {
            self
        }
    }

    /// Where the inspector shows.
    enum InspectorPlacement: String {
        /// In its own panel beside the center, when the window has room.
        case docked
        /// Over the center's trailing side, when the window is too narrow
        /// for it beside the center: still there to read, and to hide.
        case floating
        case hidden
    }

    /// The sidebar's selection.
    var screen: Screen = .overview
    /// The overview's chart, picked in its header.
    var chartStyle: ChartStyle = .ring
    /// Whether you want the inspector. It shows whenever you do, beside the
    /// center or over it (`inspectorPlacement`).
    private(set) var wantsInspector = true
    /// Whether the detail area has room for the inspector beside the center
    /// at its minimum; the window sets it as it resizes.
    var inspectorHasRoom = true
    /// The height of the overview's footer, which a floating inspector stays
    /// above so the footer's buttons stay in reach; the overview sets it.
    var overviewFooterHeight: CGFloat = 0

    var inspectorPlacement: InspectorPlacement {
        guard self.wantsInspector else { return .hidden }
        return self.inspectorHasRoom ? .docked : .floating
    }

    var inspectorShown: Bool {
        self.inspectorPlacement != .hidden
    }

    /// What the inspector's toggle and the View menu do: show or hide it. In
    /// a window too narrow for it beside the center, it floats over it; the
    /// window keeps its size.
    func toggleInspector() {
        self.wantsInspector.toggle()
    }

    /// Shows `screen`, as the sidebar does.
    func show(_ screen: Screen) {
        self.screen = screen
    }

    /// Shows the overview with `style`, as the View menu's Ring and Blocks do.
    func showChart(_ style: ChartStyle) {
        self.show(.overview)
        self.chartStyle = style
    }
}
