import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Menu commands")
struct AppCommandsTests {
    @Test
    func `the inspector item says what choosing it does`() {
        let window = WindowViewModel()
        #expect(AppCommands.inspectorTitle(shown: window.inspectorShown) == "Hide Inspector")
        window.toggleInspector()
        #expect(AppCommands.inspectorTitle(shown: window.inspectorShown) == "Show Inspector")
    }

    @Test
    func `Check for Updates… has an ellipsis, as it opens Sparkle's window`() {
        #expect(AppCommands.checkForUpdatesTitle == "Check for Updates…")
    }

    @Test
    func `the inspector moves with the sidebar's timing, and only fades with Reduce Motion`() {
        #expect(InspectorMotion.duration == 0.25)
        #expect(InspectorMotion.layoutAnimation(reduceMotion: false) == .easeInOut(duration: 0.25))
        #expect(InspectorMotion.layoutAnimation(reduceMotion: true) == nil)
    }
}
