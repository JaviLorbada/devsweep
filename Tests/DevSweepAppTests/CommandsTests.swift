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
    func `the inspector toggles, and asked for while hidden for room it stays wanted`() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        #expect(model.inspectorShown)
        model.toggleInspector()
        #expect(!model.inspectorShown && !model.wantsInspector)
        model.toggleInspector()
        #expect(model.inspectorShown)
        // Too narrow: the toggle asks the window to widen, and keeps wanting it.
        model.inspectorHasRoom = false
        #expect(!model.inspectorShown)
        model.toggleInspector()
        #expect(model.wantsInspector)
    }
}
