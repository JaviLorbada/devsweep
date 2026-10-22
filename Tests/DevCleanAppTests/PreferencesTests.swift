import DevCleanKit
import Testing
@testable import DevCleanApp

@MainActor
@Suite("Preferences")
struct PreferencesTests {
    @Test("Start from today's defaults")
    func defaults() {
        let preferences = Preferences(storage: InMemoryPreferencesStore())
        #expect(preferences.projectFolders == ["~/Developer", "~/Development", "~/dev", "~/Documents/Workspace", "~/Projects"])
        #expect(preferences.usesDefaultProjectFolders)
        #expect(preferences.skippedItems.isEmpty)
        #expect(preferences.staleDays == 90)
        #expect(preferences.moveToTrash)
        #expect(preferences.scanOnLaunch)
        // The same folders the command line searches without DEVCLEAN_PROJECT_DIRS.
        let config = preferences.scanConfig(environment: ["HOME": "/Users/someone"])
        #expect(config.projectDirectories.map { $0.replacingOccurrences(of: "~", with: "/Users/someone") }
            == ScanConfig.splitList(ScanConfig.defaultProjectDirectories(home: "/Users/someone")))
    }

    @Test("Are kept, and read back by the next launch")
    func persisted() {
        let storage = InMemoryPreferencesStore()
        let preferences = Preferences(storage: storage)
        preferences.projectFolders = ["~/Code"]
        preferences.skippedItems = [.homebrew, .npmCache]
        preferences.staleDays = 30
        preferences.moveToTrash = false
        preferences.scanOnLaunch = false

        let again = Preferences(storage: storage)
        #expect(again.projectFolders == ["~/Code"])
        #expect(again.skippedItems == [.homebrew, .npmCache])
        #expect(again.staleDays == 30)
        #expect(!again.moveToTrash)
        #expect(!again.scanOnLaunch)
    }

    @Test("Shape the window's scan, while DEVCLEAN_PROJECT_DIRS still wins")
    func scanConfig() {
        let preferences = Preferences(storage: InMemoryPreferencesStore())
        preferences.projectFolders = ["~/Code", "/Volumes/Work"]
        preferences.skippedItems = [.homebrew]
        preferences.staleDays = 45
        let config = preferences.scanConfig(environment: ["HOME": "/Users/someone"])
        #expect(config.projectDirectories == ["~/Code", "/Volumes/Work"])
        #expect(config.skipped == [.homebrew])
        #expect(config.staleDays == 45)
        #expect(config.includeAndroid)

        let overridden = preferences.scanConfig(environment: ["HOME": "/Users/someone", "DEVCLEAN_PROJECT_DIRS": "/tmp/a:/tmp/b"])
        #expect(overridden.projectDirectories == ["/tmp/a", "/tmp/b"])
    }

    @Test("Adds folders inside home with ~, once")
    func addFolder() {
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

    @Test("Keep the threshold within its range")
    func clampsStaleDays() {
        let storage = InMemoryPreferencesStore()
        storage.set(0, forKey: Preferences.Key.staleDays)
        #expect(Preferences(storage: storage).staleDays == Preferences.staleDaysRange.lowerBound)
    }

    @Test("Apply from the next scan: skipped items leave the window")
    func appliedByScan() async {
        let home = TemporaryHome()
        let model = scanningModel(home: home)
        #expect(model.scanOrder.contains(.homebrew))
        model.preferences.skippedItems = [.homebrew]
        model.preferences.staleDays = 30
        #expect(model.staleDays == 30)
        model.scan()
        #expect(!model.scanOrder.contains(.homebrew))
        #expect(model.engine?.config.skipped == [.homebrew])
        model.stopScan()
    }

    @Test("Cleaning starts out the way the preferences say")
    func cleaningMode() {
        let storage = InMemoryPreferencesStore()
        storage.set(false, forKey: Preferences.Key.moveToTrash)
        let home = TemporaryHome()
        let model = AppModel(environment: ["HOME": home.path], store: InMemoryScanStore(), preferences: Preferences(storage: storage),
                             notifier: SilentNotificationPoster(), dependencies: Dependencies(tools: .unavailable))
        #expect(!model.moveToTrash)
    }
}
