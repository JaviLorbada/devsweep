import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Menu commands")
struct CommandsTests {
    @Test
    func `the inspector item says what choosing it does, and the problem report is in title case`() {
        let home = TemporaryHome()
        let app = makeApp(home: home)
        #expect(AppCommands.inspectorTitle(shown: app.window.inspectorShown) == "Hide Inspector")
        app.window.toggleInspector()
        #expect(AppCommands.inspectorTitle(shown: app.window.inspectorShown) == "Show Inspector")
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
