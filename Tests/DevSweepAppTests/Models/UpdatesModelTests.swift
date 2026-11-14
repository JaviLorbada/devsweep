import Testing
@testable import DevSweepApp

@MainActor
@Suite("Updates")
struct UpdatesModelTests {
    @Test
    func `a build without a feed has no updater, and checks nothing`() {
        let model = UpdatesModel(updater: nil)
        #expect(!model.isAvailable)
        #expect(!model.canCheck)
        model.checkForUpdates()
        model.setChecksAutomatically(true)
        #expect(!model.checksAutomatically)
    }

    @Test
    func `Check for Updates… asks the updater, and waits while a check runs`() {
        let updater = FakeUpdater()
        let model = UpdatesModel(updater: updater)
        #expect(model.isAvailable)
        #expect(model.canCheck)
        model.checkForUpdates()
        #expect(updater.checks == 1)

        updater.setCanCheck(false)
        #expect(!model.canCheck)
        model.checkForUpdates()
        #expect(updater.checks == 1, "a check already runs")
        updater.setCanCheck(true)
        #expect(model.canCheck)
    }

    @Test
    func `automatic checks start off, and Settings turns them on in the updater`() {
        let updater = FakeUpdater()
        let model = UpdatesModel(updater: updater)
        #expect(!model.checksAutomatically, "nothing is turned on unasked")
        #expect(!model.downloadsAutomatically)

        model.setChecksAutomatically(true)
        #expect(updater.checksAutomatically)
        #expect(model.checksAutomatically)
        model.setDownloadsAutomatically(true)
        #expect(updater.downloadsAutomatically)
        #expect(model.downloadsAutomatically)
    }

    @Test
    func `Settings shows what was answered in Sparkle's own question`() {
        let updater = FakeUpdater()
        let model = UpdatesModel(updater: updater)
        updater.answer(checks: true, downloads: true)
        #expect(model.checksAutomatically)
        #expect(model.downloadsAutomatically)
        updater.answer(checks: false, downloads: false)
        #expect(!model.checksAutomatically)
        #expect(!model.downloadsAutomatically)
    }

    @Test
    func `updates never install on their own without the daily check that finds them`() {
        let updater = FakeUpdater()
        updater.downloadsAutomatically = true
        let model = UpdatesModel(updater: updater)
        #expect(!model.downloadsAutomatically)
        model.setChecksAutomatically(true)
        #expect(model.downloadsAutomatically)
        model.setChecksAutomatically(false)
        #expect(!model.downloadsAutomatically)
    }
}
