import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Window")
struct WindowViewModelTests {
    @Test
    func `Ring and Blocks show the overview with that chart`() {
        let window = WindowViewModel()
        window.show(.xcodeVersions)
        window.showChart(.blocks)
        #expect(window.screen == .overview)
        #expect(window.chartStyle == .blocks)
        window.showChart(.ring)
        #expect(window.chartStyle == .ring)
    }

    @Test
    func `the inspector toggles, docked with room and floating over the center without it`() {
        let window = WindowViewModel()
        #expect(window.inspectorPlacement == .docked)
        window.toggleInspector()
        #expect(window.inspectorPlacement == .hidden && !window.inspectorShown)
        // Hidden by hand, then the window made narrow: one press shows it,
        // floating, and the window keeps its size.
        window.inspectorHasRoom = false
        #expect(window.inspectorPlacement == .hidden)
        window.toggleInspector()
        #expect(window.inspectorPlacement == .floating && window.inspectorShown)
        window.toggleInspector()
        #expect(window.inspectorPlacement == .hidden)
        // Wanted while the window narrows, it floats rather than going away,
        // and docks again when the window widens.
        window.toggleInspector()
        window.inspectorHasRoom = true
        #expect(window.inspectorPlacement == .docked)
        window.inspectorHasRoom = false
        #expect(window.inspectorPlacement == .floating)
    }
}
