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
    static let inspector = Range(min: 260, ideal: 300, max: 380)
    /// The center column never gets narrower than this; screens must fit it.
    static let centerMinimumWidth: CGFloat = 460
    /// The lowest the window goes; columns must not ask for more height.
    static let minimumHeight: CGFloat = 560
    /// Room for the split view's dividers.
    static let dividers: CGFloat = 10

    /// The window never gets narrower than the sidebar and the center at
    /// their minimums, so nothing is ever clipped.
    static let minimumWidth = sidebar.min + centerMinimumWidth + dividers

    /// Narrower than this, the inspector collapses on its own, the way Mail
    /// and Finder do, before AppKit would have to squeeze a column. It comes
    /// back once the window is `inspectorReturnWidth` wide again.
    static let inspectorCollapseWidth = sidebar.min + centerMinimumWidth + inspector.min + dividers + 30
    static let inspectorReturnWidth = inspectorCollapseWidth + 30
}
