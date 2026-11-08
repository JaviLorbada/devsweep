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
        let wide = WindowLayout.inspectorShowFrom, narrow = WindowLayout.inspectorHideBelow - 1
        window.detailWidthChanged(wide)
        #expect(window.inspectorPlacement == .docked)
        window.toggleInspector()
        #expect(window.inspectorPlacement == .hidden && !window.inspectorShown)
        // Hidden by hand, then the window made narrow: one press shows it,
        // floating, and the window keeps its size.
        window.detailWidthChanged(narrow)
        #expect(window.inspectorPlacement == .hidden)
        window.toggleInspector()
        #expect(window.inspectorPlacement == .floating && window.inspectorShown)
        window.toggleInspector()
        #expect(window.inspectorPlacement == .hidden)
        // Wanted while the window narrows, it floats rather than going away,
        // and docks again when the window widens.
        window.toggleInspector()
        window.detailWidthChanged(wide)
        #expect(window.inspectorPlacement == .docked)
        window.detailWidthChanged(narrow)
        #expect(window.inspectorPlacement == .floating)
    }

    @Test
    func `the inspector floats below one width and docks again only from a wider one`() {
        let window = WindowViewModel()
        let between = (WindowLayout.inspectorHideBelow + WindowLayout.inspectorShowFrom) / 2
        window.detailWidthChanged(WindowLayout.inspectorHideBelow)
        #expect(window.inspectorHasRoom, "at the edge it stays docked")
        window.detailWidthChanged(WindowLayout.inspectorHideBelow - 1)
        #expect(!window.inspectorHasRoom)
        window.detailWidthChanged(between)
        #expect(!window.inspectorHasRoom, "between the two widths it stays as it was")
        window.detailWidthChanged(WindowLayout.inspectorShowFrom)
        #expect(window.inspectorHasRoom)
        window.detailWidthChanged(between)
        #expect(window.inspectorHasRoom, "and docked stays docked")
    }
}
