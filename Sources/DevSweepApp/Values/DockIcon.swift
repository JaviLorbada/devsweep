/// When the app's icon shows in the Dock and the app switcher.
enum DockIcon {
    /// Shown unless Show in Dock is off, and then still shown while a window
    /// is open, since an app without a Dock icon has no menus and so none of
    /// their shortcuts, and whenever the menu bar item is off, since without
    /// either there would be no way back to the app.
    static func isShown(showInDock: Bool, showInMenuBar: Bool, windowOpen: Bool) -> Bool {
        showInDock || windowOpen || !showInMenuBar
    }
}
