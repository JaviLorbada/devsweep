import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Preferences")
struct PreferencesTests {
    @Test
    func `start from today's defaults`() {
        let preferences = Preferences(storage: InMemoryPreferencesStore())
        #expect(preferences.projectFolders == [
            "~/Developer",
            "~/Development",
            "~/dev",
            "~/Documents/Workspace",
            "~/Projects",
        ])
        #expect(preferences.usesDefaultProjectFolders)
        #expect(preferences.skippedItems.isEmpty)
        #expect(preferences.staleDays == 90)
        #expect(preferences.moveToTrash)
        #expect(preferences.scanOnLaunch)
        #expect(preferences.showInMenuBar)
        // The same folders the command line searches without DEVSWEEP_PROJECT_DIRS.
        let config = preferences.scanConfig(environment: ["HOME": "/Users/someone"])
        #expect(config.projectDirectories.map { $0.replacingOccurrences(of: "~", with: "/Users/someone") }
            == ScanConfig.splitList(ScanConfig.defaultProjectDirectories(home: "/Users/someone")))
    }

    @Test
    func `are kept, and read back by the next launch`() {
        let storage = InMemoryPreferencesStore()
        let preferences = Preferences(storage: storage)
        preferences.projectFolders = ["~/Code"]
        preferences.skippedItems = [.homebrew, .npmCache]
        preferences.staleDays = 30
        preferences.moveToTrash = false
        preferences.scanOnLaunch = false
        preferences.showInMenuBar = false

        let again = Preferences(storage: storage)
        #expect(again.projectFolders == ["~/Code"])
        #expect(again.skippedItems == [.homebrew, .npmCache])
        #expect(again.staleDays == 30)
        #expect(!again.moveToTrash)
        #expect(!again.scanOnLaunch)
        #expect(!again.showInMenuBar)
    }

    @Test
    func `shape the window's scan, while DEVSWEEP_PROJECT_DIRS still wins`() {
        let preferences = Preferences(storage: InMemoryPreferencesStore())
        preferences.projectFolders = ["~/Code", "/Volumes/Work"]
        preferences.skippedItems = [.homebrew]
        preferences.staleDays = 45
        let config = preferences.scanConfig(environment: ["HOME": "/Users/someone"])
        #expect(config.projectDirectories == ["~/Code", "/Volumes/Work"])
        #expect(config.skipped == [.homebrew])
        #expect(config.staleDays == 45)
        #expect(config.includeAndroid)

        let overridden = preferences.scanConfig(environment: [
            "HOME": "/Users/someone",
            "DEVSWEEP_PROJECT_DIRS": "/tmp/a:/tmp/b",
        ])
        #expect(overridden.projectDirectories == ["/tmp/a", "/tmp/b"])
    }

    @Test
    func `adds folders inside home with ~, once`() {
        let preferences = Preferences(storage: InMemoryPreferencesStore())
        preferences.projectFolders = []
        preferences.addProjectFolder("/Users/someone/Code", home: "/Users/someone")
        preferences.addProjectFolder("/Users/someone/Code", home: "/Users/someone")
        preferences.addProjectFolder("/Users/someoneelse/Code", home: "/Users/someone")
        preferences.addProjectFolder("/Volumes/Work", home: "/Users/someone")
        #expect(preferences.projectFolders == ["~/Code", "/Users/someoneelse/Code", "/Volumes/Work"])
        preferences.restoreDefaultProjectFolders()
        #expect(preferences.usesDefaultProjectFolders)
    }

    @Test
    func `keep the threshold within its range`() {
        let storage = InMemoryPreferencesStore()
        storage.set(0, forKey: Preferences.Key.staleDays)
        #expect(Preferences(storage: storage).staleDays == Preferences.staleDaysRange.lowerBound)
    }

    @Test
    func `apply from the next scan: skipped items leave the window`() {
        let home = TemporaryHome()
        let model = scanningModel(home: home)
        #expect(model.scan.scanOrder.contains(.homebrew))
        model.preferences.skippedItems = [.homebrew]
        model.preferences.staleDays = 30
        #expect(model.runtimes.staleDays == 30)
        model.scan.scan()
        #expect(!model.scan.scanOrder.contains(.homebrew))
        #expect(model.scan.engine?.config.skipped == [.homebrew])
        model.scan.stopScan()
    }

    @Test
    func `cleaning starts out the way the preferences say`() {
        let storage = InMemoryPreferencesStore()
        storage.set(false, forKey: Preferences.Key.moveToTrash)
        let home = TemporaryHome()
        let model = AppModel(
            environment: ["HOME": home.path],
            store: InMemoryScanStore(),
            preferences: Preferences(storage: storage),
            notifier: SilentNotificationPoster(),
            dependencies: Dependencies(tools: .unavailable))
        #expect(!model.cleaning.moveToTrash)
    }
}
