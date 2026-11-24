import Testing
@testable import DevSweepApp

@MainActor
@Suite("Updates")
struct UpdatesModelTests {
    private let preferences = Preferences(storage: InMemoryPreferencesStore())

    private func model(_ updater: FakeUpdater?) -> UpdatesModel {
        UpdatesModel(updater: updater, preferences: self.preferences)
    }

    @Test
    func `a build without a feed has no updater, and checks nothing`() {
        let model = self.model(nil)
        #expect(!model.isAvailable)
        #expect(!model.canCheck)
        #expect(model.waitingUpdate == nil)
        model.checkForUpdates()
        model.setChecksAutomatically(true)
        #expect(!model.checksAutomatically)
    }

    @Test
    func `Check for Updates… asks the updater, and waits while a check runs`() {
        let updater = FakeUpdater()
        let model = self.model(updater)
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
        let model = self.model(updater)
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
        let model = self.model(updater)
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
        let model = self.model(updater)
        #expect(!model.downloadsAutomatically)
        model.setChecksAutomatically(true)
        #expect(model.downloadsAutomatically)
        model.setChecksAutomatically(false)
        #expect(!model.downloadsAutomatically)
    }

    @Test
    func `an update the daily check finds waits until the person looks at it, or once downloaded until it installs`() {
        let updater = FakeUpdater()
        let model = self.model(updater)
        #expect(model.waitingUpdate == nil)
        updater.setWaitingUpdate(.available)
        #expect(model.waitingUpdate == .available)
        updater.setWaitingUpdate(.ready)
        #expect(model.waitingUpdate == .ready)
        model.installUpdate()
        #expect(updater.installs == 1)
        updater.setWaitingUpdate(nil)
        #expect(model.waitingUpdate == nil)
    }

    @Test
    func `only a downloaded update installs`() {
        let updater = FakeUpdater()
        let model = self.model(updater)
        model.installUpdate()
        updater.setWaitingUpdate(.available)
        model.installUpdate()
        #expect(updater.installs == 0, "Sparkle's window decides what a found update does")
    }

    @Test
    func `an update waits as a gentle reminder only while the menu bar item can show it`() {
        let updater = FakeUpdater()
        _ = self.model(updater)
        #expect(updater.canRemindGently?() == true)
        self.preferences.showInMenuBar = false
        #expect(updater.canRemindGently?() == false, "Sparkle shows it in its own window instead")
    }
}
