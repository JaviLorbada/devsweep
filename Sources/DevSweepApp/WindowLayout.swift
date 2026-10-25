import CoreGraphics

/// The window's column sizes, shared by the views and the layout tests.
///
/// Every screen and inspector has to fit these minimums. Content that asks for
/// more than its column has makes AppKit's split view grow past the window or
/// collapse a column mid-layout, which is how the Xcode versions screen
/// crashed and the runtimes screen went blank.
enum WindowLayout {
    struct Range {
        let min: CGFloat
        let ideal: CGFloat
        let max: CGFloat
    }

    static let sidebar = Range(min: 200, ideal: 232, max: 300)
    /// The inspector is a fixed column at the right of the detail area.
    static let inspectorWidth: CGFloat = 300
    /// The center column never gets narrower than this; screens must fit it.
    static let centerMinimumWidth: CGFloat = 460
    /// The lowest the window goes; columns must not ask for more height.
    static let minimumHeight: CGFloat = 560
    /// Room for the split view's dividers.
    static let dividers: CGFloat = 10
    /// The space around and between the rounded panels the columns sit in.
    static let gap: CGFloat = 8
    /// The sidebar's corner radius, which is concentric with the window's
    /// 26-point corner at the 8-point gap. The panels use it wherever they
    /// don't meet a window corner.
    static let panelCornerRadius: CGFloat = 18

    /// The window never gets narrower than the sidebar and the center at
    /// their minimums, so nothing is ever clipped.
    static let minimumWidth = sidebar.min + dividers + gap + centerMinimumWidth + gap

    /// The widest the sidebar may be in a window `width` points wide: what
    /// the center at its minimum leaves, between the sidebar's own limits.
    /// The sidebar sits a gap in from the window's edge, and the center a gap
    /// from each side of it. A sidebar dragged wide in a wide window gives way
    /// as the window narrows; AppKit kept it, and the split view grew past
    /// the window, cutting off the sidebar's leading edge and the center's
    /// trailing one.
    static func sidebarMaximum(forWindowWidth width: CGFloat) -> CGFloat {
        min(self.sidebar.max, max(self.sidebar.min, width - (self.gap + self.gap + self.centerMinimumWidth + self.gap)))
    }

    /// The detail area holds the center at its minimum and the inspector,
    /// each in its panel.
    static let detailWidthWithInspector = gap + centerMinimumWidth + gap + inspectorWidth + gap
    /// The inspector hides, the way Mail collapses a pane, when the detail
    /// area gets narrower than this, before the center would have to go
    /// below its minimum; it comes back from `inspectorShowFrom`, a little
    /// wider, so it doesn't flicker at the edge. With the sidebar at its usual
    /// width that is about 1000 points of window.
    static let inspectorHideBelow = detailWidthWithInspector + 20
    static let inspectorShowFrom = detailWidthWithInspector + 40
}
