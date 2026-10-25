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
        model.screen = .xcodeVersions
        model.showChart(.blocks)
        #expect(model.screen == .overview)
        #expect(model.chartStyle == .blocks)
        model.showChart(.ring)
        #expect(model.chartStyle == .ring)
    }

    @Test
    func `the inspector toggles, docked with room and floating over the center without it`() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        #expect(model.inspectorPlacement == .docked)
        model.toggleInspector()
        #expect(model.inspectorPlacement == .hidden && !model.inspectorShown)
        // Hidden by hand, then the window made narrow: one press shows it,
        // floating, and the window keeps its size.
        model.inspectorHasRoom = false
        #expect(model.inspectorPlacement == .hidden)
        model.toggleInspector()
        #expect(model.inspectorPlacement == .floating && model.inspectorShown)
        model.toggleInspector()
        #expect(model.inspectorPlacement == .hidden)
        // Wanted while the window narrows, it floats rather than going away,
        // and docks again when the window widens.
        model.toggleInspector()
        model.inspectorHasRoom = true
        #expect(model.inspectorPlacement == .docked)
        model.inspectorHasRoom = false
        #expect(model.inspectorPlacement == .floating)
    }

    @Test
    func `the inspector item says what choosing it does, and the problem report is in title case`() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        #expect(AppCommands.inspectorTitle(shown: model.inspectorShown) == "Hide Inspector")
        model.toggleInspector()
        #expect(AppCommands.inspectorTitle(shown: model.inspectorShown) == "Show Inspector")
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
