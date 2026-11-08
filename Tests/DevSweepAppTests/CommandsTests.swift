import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Menu commands")
struct CommandsTests {
    @Test
    func `Ring and Blocks show the overview with that chart`() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        model.window.screen = .xcodeVersions
        model.window.showChart(.blocks)
        #expect(model.window.screen == .overview)
        #expect(model.window.chartStyle == .blocks)
        model.window.showChart(.ring)
        #expect(model.window.chartStyle == .ring)
    }

    @Test
    func `the inspector toggles, docked with room and floating over the center without it`() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        #expect(model.window.inspectorPlacement == .docked)
        model.window.toggleInspector()
        #expect(model.window.inspectorPlacement == .hidden && !model.window.inspectorShown)
        // Hidden by hand, then the window made narrow: one press shows it,
        // floating, and the window keeps its size.
        model.window.inspectorHasRoom = false
        #expect(model.window.inspectorPlacement == .hidden)
        model.window.toggleInspector()
        #expect(model.window.inspectorPlacement == .floating && model.window.inspectorShown)
        model.window.toggleInspector()
        #expect(model.window.inspectorPlacement == .hidden)
        // Wanted while the window narrows, it floats rather than going away,
        // and docks again when the window widens.
        model.window.toggleInspector()
        model.window.inspectorHasRoom = true
        #expect(model.window.inspectorPlacement == .docked)
        model.window.inspectorHasRoom = false
        #expect(model.window.inspectorPlacement == .floating)
    }

    @Test
    func `the inspector item says what choosing it does, and the problem report is in title case`() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        #expect(AppCommands.inspectorTitle(shown: model.window.inspectorShown) == "Hide Inspector")
        model.window.toggleInspector()
        #expect(AppCommands.inspectorTitle(shown: model.window.inspectorShown) == "Show Inspector")
        #expect(AppCommands.reportProblemTitle == "Report a Problem")
        #expect(AppCommands.supportTitle == "Support DevSweep")
    }

    @Test
    func `the inspector moves with the sidebar's timing, and only fades with Reduce Motion`() {
        #expect(InspectorMotion.duration == 0.25)
        #expect(InspectorMotion.layoutAnimation(reduceMotion: false) == .easeInOut(duration: 0.25))
        #expect(InspectorMotion.layoutAnimation(reduceMotion: true) == nil)
    }
}
