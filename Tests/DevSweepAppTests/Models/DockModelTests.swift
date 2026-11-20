import Testing
@testable import DevSweepApp

@MainActor
@Suite("Dock")
struct DockModelTests {
    /// The menu bar item on and Show in Dock off: a menu-bar-only app.
    private func menuBarOnly() -> Preferences {
        let preferences = Preferences(storage: InMemoryPreferencesStore())
        preferences.showInDock = false
        return preferences
    }

    @Test
    func `the icon stays by default, as the window opens and closes`() {
        let dockIcon = FakeDockIcon()
        let dock = DockModel(preferences: Preferences(storage: InMemoryPreferencesStore()), dockIcon: dockIcon)
        dock.opened(.main)
        dock.closed(.main)
        #expect(dockIcon.changes.isEmpty)
        #expect(dock.isIconShown)
    }

    @Test
    func `with Show in Dock off, the icon goes once the last window closes`() {
        let dockIcon = FakeDockIcon()
        let dock = DockModel(preferences: self.menuBarOnly(), dockIcon: dockIcon)
        dock.opened(.main)
        dock.opened(.settings)
        dock.closed(.main)
        #expect(dockIcon.changes.isEmpty, "Settings is still open")
        dock.closed(.settings)
        #expect(dockIcon.changes == [false])
        #expect(!dock.isIconShown)
    }

    @Test
    func `the icon comes back while a window is open, for the menus`() {
        let dockIcon = FakeDockIcon()
        let dock = DockModel(preferences: self.menuBarOnly(), dockIcon: dockIcon)
        dock.opened(.main)
        dock.closed(.main)
        dock.opened(.main)
        #expect(dockIcon.changes == [false, true])
        dock.closed(.main)
        dock.opened(.settings)
        #expect(dockIcon.changes == [false, true, false, true])
    }

    @Test
    func `Show in Dock turned off in Settings takes the icon once Settings closes`() {
        let preferences = Preferences(storage: InMemoryPreferencesStore())
        let dockIcon = FakeDockIcon()
        let dock = DockModel(preferences: preferences, dockIcon: dockIcon)
        dock.opened(.settings)
        preferences.showInDock = false
        dock.closed(.settings)
        #expect(dockIcon.changes == [false])
    }

    @Test
    func `without the menu bar item the icon stays, whatever the setting`() {
        let preferences = self.menuBarOnly()
        preferences.showInMenuBar = false
        let dockIcon = FakeDockIcon()
        let dock = DockModel(preferences: preferences, dockIcon: dockIcon)
        dock.opened(.main)
        dock.closed(.main)
        #expect(dockIcon.changes.isEmpty)
    }

    @Test
    func `the menu bar item dragged out while every window is closed brings the icon back`() async {
        let preferences = self.menuBarOnly()
        let dockIcon = FakeDockIcon()
        let dock = DockModel(preferences: preferences, dockIcon: dockIcon)
        dock.opened(.main)
        dock.closed(.main)
        #expect(dockIcon.changes == [false])

        preferences.showInMenuBar = false
        await waitUntil { dockIcon.changes.count == 2 }
        #expect(dockIcon.changes == [false, true])
        #expect(dock.isIconShown)
    }
}
