import Testing
@testable import DevSweepApp

@Suite("A waiting update")
struct WaitingUpdateTests {
    @Test
    func `the row asks for Sparkle's window while the update is only found, and installs it once downloaded`() {
        // An ellipsis where Sparkle's window asks what to do next; none where
        // choosing the row does it.
        #expect(WaitingUpdate.available.title == "Update Available…")
        #expect(WaitingUpdate.ready.title == "Install Update and Relaunch")
    }

    @Test
    func `debug runs name a state as the launch argument does`() {
        #expect(WaitingUpdate(rawValue: "available") == .available)
        #expect(WaitingUpdate(rawValue: "ready") == .ready)
        #expect(WaitingUpdate(rawValue: "") == nil)
    }
}
