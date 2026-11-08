import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Running apps")
struct RunningAppsModelTests {
    @Test
    func `it says what is open, and quitting asks those apps, then looks again`() async {
        let apps = FakeDeveloperApps(running: [.simulator, .xcode])
        let model = RunningAppsModel(checker: apps, quitter: apps)
        #expect(model.running.isEmpty, "nothing is known before it looks")
        await model.refresh()
        #expect(model.open == [.xcode, .simulator])
        #expect(model.sentence == "Xcode and Simulator are open.")

        #expect(await model.quit(model.open))
        #expect(apps.asked == [[.xcode, .simulator]])
        #expect(model.running.isEmpty)
        #expect(model.sentence == "Xcode and Simulator are closed.")
    }

    @Test
    func `an app that won't quit stays open`() async {
        let apps = FakeDeveloperApps(running: [.xcode], quits: false)
        let model = RunningAppsModel(checker: apps, quitter: apps)
        #expect(await !model.quit([.xcode]))
        #expect(model.running == [.xcode])
    }
}
