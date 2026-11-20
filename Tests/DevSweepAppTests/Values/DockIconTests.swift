import Testing
@testable import DevSweepApp

@Suite("Dock icon")
struct DockIconTests {
    @Test
    func `shows by default, windows open or not`() {
        #expect(DockIcon.isShown(showInDock: true, showInMenuBar: true, windowOpen: true))
        #expect(DockIcon.isShown(showInDock: true, showInMenuBar: true, windowOpen: false))
    }

    @Test
    func `goes with Show in Dock off once every window is closed`() {
        #expect(!DockIcon.isShown(showInDock: false, showInMenuBar: true, windowOpen: false))
    }

    @Test
    func `shows while a window is open, so the menus and their shortcuts work`() {
        #expect(DockIcon.isShown(showInDock: false, showInMenuBar: true, windowOpen: true))
    }

    @Test
    func `shows without the menu bar item, whatever the setting, or there would be no way back`() {
        #expect(DockIcon.isShown(showInDock: false, showInMenuBar: false, windowOpen: false))
    }
}
