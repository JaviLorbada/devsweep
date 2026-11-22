import CoreGraphics

/// The Settings window's sizes. It opens as wide as it always was and tall
/// enough for General whole, and resizes from its edges; a tab taller than
/// the window scrolls.
enum SettingsLayout {
    /// The width every tab was laid out for, when Settings had a fixed size.
    /// Settings opens this wide and gets no narrower.
    static let width: CGFloat = 540
    /// The tabs' content at its shortest: about as short as Settings was,
    /// which still shows the Folders tab whole.
    static let minimumHeight: CGFloat = 360
    /// The tabs' content as Settings opens: General whole, its updates
    /// included.
    static let idealHeight: CGFloat = 705
    /// Settings' title bar and the tabs under it. The scene's default size
    /// counts them; the content's frame doesn't.
    static let toolbarHeight: CGFloat = 88
    /// The window as it opens.
    static let windowHeight = idealHeight + toolbarHeight
}
