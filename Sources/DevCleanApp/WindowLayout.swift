import CoreGraphics

/// The window's column sizes, shared by the views and the layout tests.
///
/// Every screen and inspector has to fit these minimums. Content that asks for
/// more than its column has makes AppKit's split view grow past the window or
/// collapse a column mid-layout, which is how the Xcode versions screen
/// crashed and the runtimes screen went blank.
enum WindowLayout {
    /// The center column never gets narrower than this; screens must fit it.
    static let centerMinimumWidth: CGFloat = 460
    /// The lowest the window goes; columns must not ask for more height.
    static let minimumHeight: CGFloat = 560
}
