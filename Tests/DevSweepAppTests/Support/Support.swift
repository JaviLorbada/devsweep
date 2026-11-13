import AppKit
import DevSweepKit
import Foundation
import SwiftUI
@testable import DevSweepApp

/// A temp folder standing in for HOME, removed when the test lets go of it.
final class TemporaryHome: @unchecked Sendable {
    let root: String
    let path: String

    init() {
        let base = FileManager.default.temporaryDirectory.path(percentEncoded: false)
        self.root = (base.hasSuffix("/") ? base : base + "/") + "devsweep-app-tests-\(UUID().uuidString)"
        self.path = "\(self.root)/home"
        must { try FileManager.default.createDirectory(atPath: self.path, withIntermediateDirectories: true) }
    }

    deinit {
        precondition(root.contains("/devsweep-app-tests-"), "refusing to remove \(root)")
        try? FileManager.default.removeItem(atPath: root)
    }
}

/// Test setup that must not fail: a failure stops the run with the error.
func must<T>(_ body: () throws -> T, file: StaticString = #file, line: UInt = #line) -> T {
    do {
        return try body()
    } catch {
        preconditionFailure("setup failed: \(error)", file: file, line: line)
    }
}

func write(_ kilobytes: Int, to folder: String) {
    must { try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true) }
    FileManager.default.createFile(atPath: "\(folder)/blob", contents: Data(count: kilobytes * 1024))
}

/// A home with four items of different sizes: npm's cache the smallest.
func writeFourItems(in home: TemporaryHome) {
    write(256, to: "\(home.path)/Library/Developer/Xcode/DerivedData/Atlas-abc")
    write(192, to: "\(home.path)/Library/Caches/org.swift.swiftpm")
    write(128, to: "\(home.path)/Library/Caches/CocoaPods")
    write(16, to: "\(home.path)/.npm/_cacache")
}

/// Waits, up to about four seconds, for `condition`.
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
        try? await Task.sleep(for: .milliseconds(20))
    }
}

// MARK: A scan on its own

/// A scan of a temp home with none of the tools, so nothing outside the temp
/// folder runs. Its last scan is kept in memory unless `store` is nil, which
/// keeps it in the temp home's own file.
/// The environment the app's tests scan in: everything inside the fake home,
/// so no test measures the Xcodes in the Mac's own /Applications. On a CI
/// runner with several, that made scans take minutes and tests time out.
func testEnvironment(home: TemporaryHome, projectFolders: String = "") -> [String: String] {
    [
        "HOME": home.path,
        "DEVSWEEP_PROJECT_DIRS": projectFolders,
        "DEVSWEEP_APPLICATIONS_DIRS": home.path + "/Applications",
    ]
}

@MainActor
func makeScan(
    home: TemporaryHome,
    store: (any ScanMemoryStore)? = InMemoryScanStore(),
    preferences: Preferences = Preferences(storage: InMemoryPreferencesStore())) -> ScanModel
{
    ScanModel(
        environment: testEnvironment(home: home),
        store: store,
        preferences: preferences,
        dependencies: Dependencies(tools: .unavailable))
}

/// Scans and waits for the items, the extras and Android Studio.
@MainActor
func finishScan(_ scan: ScanModel) async {
    scan.scan()
    for _ in 0..<200 where scan.isScanning || scan.isLoadingExtras {
        try? await Task.sleep(for: .milliseconds(50))
    }
}

// MARK: The whole app, for the coordinator, the views and the flows

/// The whole app on an empty fake home, never scanned, holding the given
/// extras: what the views and the menus read.
@MainActor
func makeApp(home: TemporaryHome, extras: Extras? = nil) -> AppCoordinator {
    let app = AppCoordinator(
        environment: testEnvironment(home: home),
        store: InMemoryScanStore(),
        preferences: Preferences(storage: InMemoryPreferencesStore()),
        notifier: SilentNotificationPoster(),
        dependencies: Dependencies(tools: .unavailable))
    app.scan.showListings(extras: extras, android: nil)
    return app
}

/// The smallest size a view accepts: what AppKit asks the window's columns
/// for when it decides how wide and tall they must be.
@MainActor
func minimumSize(of view: some View, app: AppCoordinator) -> CGSize {
    NSHostingController(rootView: view.environment(models: app)).sizeThatFits(in: .zero)
}

/// The whole app on a fake home whose Trash is a folder in the temp folder
/// and whose Xcode and Simulator are `apps`, scanned once.
@MainActor
func scannedApp(
    home: TemporaryHome,
    apps: FakeDeveloperApps = FakeDeveloperApps(),
    projectFolders: String = "",
    files: (any FileSystemAccess)? = nil) async -> AppCoordinator
{
    var tools = Tools.unavailable
    tools.trash = FolderTrash(folder: "\(home.root)/Trash")
    tools.runningApps = apps
    let app = AppCoordinator(
        environment: testEnvironment(home: home, projectFolders: projectFolders),
        store: InMemoryScanStore(),
        preferences: Preferences(storage: InMemoryPreferencesStore()),
        notifier: SilentNotificationPoster(),
        dependencies: files.map { Dependencies(tools: tools, files: $0) } ?? Dependencies(tools: tools),
        quitter: apps)
    await finishScan(app.scan)
    return app
}

/// The whole app on a temp home with none of the tools, never scanned; its
/// last scan is kept in the temp home's own file.
@MainActor
func scanningApp(home: TemporaryHome, notifier: NotificationPoster = SilentNotificationPoster()) -> AppCoordinator {
    AppCoordinator(
        environment: testEnvironment(home: home),
        preferences: Preferences(storage: InMemoryPreferencesStore()),
        notifier: notifier,
        dependencies: Dependencies(tools: .unavailable))
}
