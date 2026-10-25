import CoreGraphics
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

    @Test
    func `one press shows the inspector in a narrow window, widening it by what the detail area lacks`() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        var widened: [CGFloat] = []
        model.widenWindow = { widened.append($0) }
        // Hidden by hand, then the window made narrow: one press shows it.
        model.toggleInspector()
        #expect(!model.wantsInspector && widened.isEmpty)
        model.inspectorHasRoom = false
        model.detailWidth = 700
        model.toggleInspector()
        #expect(model.wantsInspector)
        let missing: CGFloat = WindowLayout.inspectorShowFrom + 2 - 700
        #expect(widened == [missing])
        // The window from the recording: 1066 points, the width the old
        // fixed target asked for, with the sidebar dragged to 298, which
        // leaves 758 for the detail area. It still has to grow.
        model.detailWidth = 758
        model.toggleInspector()
        let more: CGFloat = WindowLayout.inspectorShowFrom + 2 - 758
        #expect(widened == [missing, more])
        // With room, a press hides it and asks for nothing.
        model.inspectorHasRoom = true
        model.toggleInspector()
        #expect(!model.wantsInspector && widened.count == 2)
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
