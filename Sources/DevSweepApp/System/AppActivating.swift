/// DevSweep itself: brought to the front, or quit. Live, `NSApplication`
/// does it; tests keep what was asked, so none activates or quits the test
/// runner.
@MainActor
protocol AppActivating {
    func activate()
    func terminate()
}
