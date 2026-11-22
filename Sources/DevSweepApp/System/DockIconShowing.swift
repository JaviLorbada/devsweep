/// Puts the app in the Dock and the app switcher, or takes it out. Live, the
/// app's activation policy does it; tests keep what was asked, so none
/// changes the test runner's.
@MainActor
protocol DockIconShowing {
    func setShown(_ shown: Bool)
}
