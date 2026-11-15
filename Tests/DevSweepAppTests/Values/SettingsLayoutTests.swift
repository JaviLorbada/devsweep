import Testing
@testable import DevSweepApp

@Suite("Settings layout")
struct SettingsLayoutTests {
    @Test
    func `Settings can be made shorter than it opens, and no narrower than it was`() {
        #expect(SettingsLayout.minimumHeight < SettingsLayout.idealHeight)
        // The fixed width every tab was laid out for.
        #expect(SettingsLayout.width == 540)
    }

    @Test
    func `Settings opens whole on a 13-inch MacBook Air`() {
        // Its screen is 956 points tall by default; the menu bar beside the
        // notch takes about 38 and the Dock about 70.
        #expect(SettingsLayout.windowHeight + 38 + 70 <= 956)
    }
}
