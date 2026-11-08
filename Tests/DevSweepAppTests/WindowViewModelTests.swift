import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Window")
struct WindowViewModelTests {
    @Test
    func `Ring and Blocks show the overview with that chart`() {
        let home = TemporaryHome()
        let app = makeApp(home: home, extras: sampleExtras)
        app.window.screen = .xcodeVersions
        app.window.showChart(.blocks)
        #expect(app.window.screen == .overview)
        #expect(app.window.chartStyle == .blocks)
        app.window.showChart(.ring)
        #expect(app.window.chartStyle == .ring)
    }

    @Test
    func `the inspector toggles, docked with room and floating over the center without it`() {
        let home = TemporaryHome()
        let app = makeApp(home: home)
        #expect(app.window.inspectorPlacement == .docked)
        app.window.toggleInspector()
        #expect(app.window.inspectorPlacement == .hidden && !app.window.inspectorShown)
        // Hidden by hand, then the window made narrow: one press shows it,
        // floating, and the window keeps its size.
        app.window.inspectorHasRoom = false
        #expect(app.window.inspectorPlacement == .hidden)
        app.window.toggleInspector()
        #expect(app.window.inspectorPlacement == .floating && app.window.inspectorShown)
        app.window.toggleInspector()
        #expect(app.window.inspectorPlacement == .hidden)
        // Wanted while the window narrows, it floats rather than going away,
        // and docks again when the window widens.
        app.window.toggleInspector()
        app.window.inspectorHasRoom = true
        #expect(app.window.inspectorPlacement == .docked)
        app.window.inspectorHasRoom = false
        #expect(app.window.inspectorPlacement == .floating)
    }
}
