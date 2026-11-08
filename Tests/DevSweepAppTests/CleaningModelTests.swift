import DevSweepKit
import Dispatch
import Foundation
import Synchronization
import Testing
@testable import DevSweepApp

/// The disk as it is, except that deleting removes nothing: it reports 32 KB
/// gone, then waits until the test lets it go.
final class HeldDelete: FileSystemAccess {
    private let release = DispatchSemaphore(value: 0)
    private let disk = LiveFileSystem()

    func childNames(_ directory: String) -> [String] { self.disk.childNames(directory) }
    func isDirectory(_ path: String) -> Bool { self.disk.isDirectory(path) }
    func isSymlink(_ path: String) -> Bool { self.disk.isSymlink(path) }
    func exists(_ path: String) -> Bool { self.disk.exists(path) }
    func modificationTime(_ path: String) -> Int { self.disk.modificationTime(path) }
    func contents(of path: String) -> Data? { self.disk.contents(of: path) }

    func remove(_ path: String, progress: @escaping @Sendable (Int64) -> Void) throws {
        progress(32 * 1024)
        self.release.wait()
    }

    func letGo() {
        self.release.signal()
    }
}

/// Xcode is open; Simulator isn't.
struct XcodeOpen: RunningAppsChecking {
    func isRunning(_ app: DeveloperApp) async -> Bool { app == .xcode }
}

/// Nothing is running.
struct NothingRunning: RunningAppsChecking {
    func isRunning(_ app: DeveloperApp) async -> Bool { false }
}

@MainActor
@Suite("Cleaning whole items")
struct CleaningModelTests {
    @Test
    func `with Xcode open, DerivedData asks to quit it, then Quit and Clean quits it and cleans`() async throws {
        let home = TemporaryHome()
        let folder = "\(home.path)/Library/Developer/Xcode/DerivedData/Atlas-abc"
        write(64, to: folder)
        let apps = FakeDeveloperApps(running: [.xcode])
        let app = await scannedApp(home: home, apps: apps)
        let kilobytes = try #require(app.scan.rows[.derivedData]?.kilobytes)

        await app.cleaning.requestClean([.derivedData])
        let pending = try #require(app.cleaning.pendingClean)
        guard case .quitApps([.xcode]) = pending.stage else {
            Issue.record("expected to be asked to quit Xcode")
            return
        }
        #expect(FileManager.default.fileExists(atPath: folder), "nothing goes before the answer")

        await app.cleaning.quitAppsAndClean(pending)
        await waitUntil { app.scan.rows[.derivedData]?.state == .cleaned }
        #expect(apps.asked == [[.xcode]])
        #expect(app.scan.rows[.derivedData]?.state == .cleaned)
        #expect(!FileManager.default.fileExists(atPath: folder))
        #expect(app.cleaning.trashedThisSession == kilobytes)
        #expect(!app.marks.marked.contains(.derivedData))
    }

    @Test
    func `when Xcode won't quit, nothing is cleaned and a notice says so`() async throws {
        let home = TemporaryHome()
        let folder = "\(home.path)/Library/Developer/Xcode/DerivedData/Atlas-abc"
        write(64, to: folder)
        let app = await scannedApp(home: home, apps: FakeDeveloperApps(running: [.xcode], quits: false))

        await app.cleaning.requestClean([.derivedData])
        let pending = try #require(app.cleaning.pendingClean)
        await app.cleaning.quitAppsAndClean(pending)

        #expect(app.cleaning.notice?.title == "Xcode didn't quit")
        #expect(app.cleaning.pendingClean == nil)
        #expect(app.scan.rows[.derivedData]?.state == .measured)
        #expect(FileManager.default.fileExists(atPath: folder))
    }

    @Test
    func `moving to the Trash cleans at once, and Put Back brings the whole item back`() async throws {
        let home = TemporaryHome()
        let folder = "\(home.path)/.npm/_cacache"
        write(64, to: folder)
        let app = await scannedApp(home: home)
        let kilobytes = try #require(app.scan.rows[.npmCache]?.kilobytes)

        await app.cleaning.requestClean([.npmCache])
        await waitUntil { app.scan.rows[.npmCache]?.state == .cleaned }
        #expect(app.cleaning.pendingClean == nil, "the Trash needs no question")
        #expect(!FileManager.default.fileExists(atPath: folder))
        #expect(app.scan.rows[.npmCache]?.canPutBack == true)
        #expect(app.cleaning.trashedThisSession == kilobytes)
        #expect(app.overview.statusLine.contains("moved to Trash this session"))

        await app.cleaning.putBack(.npmCache)
        #expect(FileManager.default.fileExists(atPath: folder))
        #expect(app.scan.rows[.npmCache]?.state == .measured)
        #expect(app.cleaning.trashedThisSession == 0)
    }

    @Test
    func `deleting for good, and what simctl or brew removes, asks first`() {
        let home = TemporaryHome()
        let app = makeApp(home: home)
        #expect(app.cleaning.moveToTrash)
        #expect(!app.cleaning.needsConfirmation([.npmCache, .derivedData]))
        #expect(app.cleaning.needsConfirmation([.npmCache, .homebrew]))
        #expect(app.cleaning.needsConfirmation([.simulators]))
        app.cleaning.moveToTrash = false
        #expect(app.cleaning.needsConfirmation([.npmCache]))
    }

    @Test
    func `while deleting, the row counts down what is left and Scan Again waits`() async throws {
        let home = TemporaryHome()
        write(64, to: "\(home.path)/.npm/_cacache")
        let files = HeldDelete()
        defer { files.letGo() }
        let app = AppCoordinator(
            environment: ["HOME": home.path, "DEVSWEEP_PROJECT_DIRS": ""],
            store: InMemoryScanStore(),
            preferences: Preferences(storage: InMemoryPreferencesStore()),
            notifier: SilentNotificationPoster(),
            dependencies: Dependencies(tools: .unavailable, files: files))
        await finishScan(app)
        #expect(app.scan.canScanOrStop)
        let kilobytes = try #require(app.scan.rows[.npmCache]?.kilobytes)

        app.cleaning.moveToTrash = false
        await app.cleaning.requestClean([.npmCache])
        for _ in 0..<100 where app.cleaning.pendingClean == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let pending = try #require(app.cleaning.pendingClean)
        let cleaning = Task { await app.cleaning.confirmClean(pending) }
        for _ in 0..<200 where (app.scan.rows[.npmCache]?.removedBytes ?? 0) == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(app.scan.isCleaning)
        #expect(!app.scan.canScanOrStop)
        app.scan.scan()
        #expect(!app.scan.isScanning, "a scan waits for the clean")
        let row = try #require(app.scan.rows[.npmCache])
        #expect(row.leftKilobytes == kilobytes - 32)
        #expect(row.cleaningProgress == Double(32) / Double(kilobytes))

        files.letGo()
        await cleaning.value
        #expect(app.scan.canScanOrStop)
        #expect(app.scan.rows[.npmCache]?.state == .cleaned)
        #expect(app.scan.rows[.npmCache]?.cleaningProgress == nil)
    }
}

@MainActor
@Suite("Cleaning parts of DerivedData")
struct PartsCleaningTests {
    /// An app that has scanned a DerivedData folder with the compilation
    /// cache and two projects, moving things to a Trash folder in the temp home.
    func scanned(
        _ home: TemporaryHome,
        runningApps: any RunningAppsChecking = NothingRunning()) async -> AppCoordinator
    {
        let folder = "\(home.path)/Library/Developer/Xcode/DerivedData"
        write(64, to: "\(folder)/CompilationCache.noindex")
        for project in ["Atlas", "Fieldwork"] {
            write(32, to: "\(folder)/\(project)-abc")
            FileManager.default.createFile(
                atPath: "\(folder)/\(project)-abc/info.plist",
                contents: Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <plist version="1.0"><dict><key>WorkspacePath</key>\
                <string>\(home.path)/Workspace/\(project)/\(project).xcodeproj</string></dict></plist>
                """.utf8))
        }
        var tools = Tools.unavailable
        tools.trash = FolderTrash(folder: "\(home.root)/Trash")
        tools.runningApps = runningApps
        let app = AppCoordinator(
            environment: ["HOME": home.path, "DEVSWEEP_PROJECT_DIRS": ""],
            store: InMemoryScanStore(),
            preferences: Preferences(storage: InMemoryPreferencesStore()),
            notifier: SilentNotificationPoster(),
            dependencies: Dependencies(tools: tools))
        await finishScan(app)
        return app
    }

    func project(_ name: String, in app: AppCoordinator) throws -> String {
        try #require(app.scan.rows[.derivedData]?.result?.derivedData?.projects.first {
            $0.folder.hasSuffix("/\(name)-abc")
        }).folder
    }

    @Test
    func `ticking a project cleans just it, says so, and Put Back brings it back`() async throws {
        let home = TemporaryHome()
        let app = await scanned(home)
        let atlas = try project("Atlas", in: app)
        let before = try #require(app.scan.rows[.derivedData]?.result)
        let atlasKilobytes = before.kilobytes(of: .folder(atlas))
        #expect(app.cleaning.moveToTrash)

        app.marks.setMarked(.folder(atlas), of: .derivedData, true)
        #expect(app.scan.kilobytes(of: app.marks.markedParts(of: .derivedData), in: .derivedData) == atlasKilobytes)
        await app.cleaning.requestCleanParts(of: .derivedData)
        for _ in 0..<200 where app.cleaning.lastPartsClean(of: .derivedData) == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }

        let clean = try #require(app.cleaning.lastPartsClean(of: .derivedData))
        #expect(clean.summary == "1 project")
        #expect(clean.canPutBack)
        #expect(!FileManager.default.fileExists(atPath: atlas))
        #expect(try FileManager.default.fileExists(atPath: self.project("Fieldwork", in: app)))
        let left = try #require(app.scan.rows[.derivedData]?.result)
        #expect(left.kilobytes == before.kilobytes - atlasKilobytes)
        #expect(left.derivedData?.projects.count == 1)
        #expect(app.scan.rows[.derivedData]?.state == .measured)
        #expect(app.marks.markedParts(of: .derivedData).isEmpty)
        #expect(app.cleaning.trashedThisSession == atlasKilobytes)

        await app.cleaning.putBackParts(of: .derivedData)
        #expect(FileManager.default.fileExists(atPath: atlas))
        #expect(app.scan.rows[.derivedData]?.result == before)
        #expect(app.cleaning.lastPartsClean(of: .derivedData) == nil)
        #expect(app.cleaning.trashedThisSession == 0)
    }

    @Test
    func `the shared cache asks to quit Xcode, and a project alone asks first while Xcode is open`() async throws {
        let home = TemporaryHome()
        let app = await scanned(home, runningApps: XcodeOpen())
        let atlas = try project("Atlas", in: app)

        app.marks.setMarked(.compilationCache, of: .derivedData, true)
        app.marks.setMarked(.folder(atlas), of: .derivedData, true)
        await app.cleaning.requestCleanParts(of: .derivedData)
        let quit = try #require(app.cleaning.pendingClean)
        guard case .quitApps([.xcode]) = quit.stage else {
            Issue.record("expected to be asked to quit Xcode")
            return
        }
        #expect(quit.hasOthers)
        #expect(CleanPrompt.message(for: quit, moveToTrash: true).hasPrefix(
            "The compilation cache can't be cleaned while Xcode is open."))

        // Clean the Others: the project, once asked again with Xcode open.
        app.cleaning.cleanSkippingXcodeItems(quit)
        for _ in 0..<100 where app.cleaning.pendingClean == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let confirm = try #require(app.cleaning.pendingClean)
        #expect(confirm.parts == [.folder(atlas)])
        #expect(CleanPrompt.message(for: confirm, moveToTrash: true)
            == "DerivedData for Atlas goes to the Trash, so it can be put back. Xcode is open: if Atlas is open in "
            + "it, close it there first. Xcode builds it again either way.")
        #expect(FileManager.default.fileExists(atPath: atlas), "nothing goes before the answer")
    }
}

@MainActor
@Suite("Cleaning single build folders")
struct FolderCleaningTests {
    @Test
    func `ticking a .build folder cleans just it, and Put Back brings it back`() async throws {
        let home = TemporaryHome()
        let projects = "\(home.path)/Workspace"
        for (name, kilobytes) in [("Atlas", 256), ("Fieldwork", 64)] {
            write(kilobytes, to: "\(projects)/\(name)/.build/debug")
            FileManager.default.createFile(atPath: "\(projects)/\(name)/Package.swift", contents: Data())
        }
        var tools = Tools.unavailable
        tools.trash = FolderTrash(folder: "\(home.root)/Trash")
        let app = AppCoordinator(
            environment: ["HOME": home.path, "DEVSWEEP_PROJECT_DIRS": projects],
            store: InMemoryScanStore(),
            preferences: Preferences(storage: InMemoryPreferencesStore()),
            notifier: SilentNotificationPoster(),
            dependencies: Dependencies(tools: tools))
        await finishScan(app)
        let before = try #require(app.scan.rows[.swiftpmBuilds]?.result)
        #expect(PartsList.listsFolders(before))
        let atlas = try #require(before.paths.first { $0.hasSuffix("/Atlas/.build") })
        #expect(PartsList.folderNames(before.paths)[atlas] == "Atlas")

        app.marks.setMarked(.folder(atlas), of: .swiftpmBuilds, true)
        #expect(CleanPrompt.partsSummary(app.marks.markedParts(of: .swiftpmBuilds), in: .swiftpmBuilds) == "1 folder")
        await app.cleaning.requestCleanParts(of: .swiftpmBuilds)
        for _ in 0..<200 where app.cleaning.lastPartsClean(of: .swiftpmBuilds) == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(!FileManager.default.fileExists(atPath: atlas))
        let left = try #require(app.scan.rows[.swiftpmBuilds]?.result)
        #expect(left.paths.count == 1)
        #expect(left.label == "SwiftPM .build folders (1)")
        #expect(left.kilobytes == before.kilobytes - before.kilobytes(of: .folder(atlas)))

        await app.cleaning.putBackParts(of: .swiftpmBuilds)
        #expect(FileManager.default.fileExists(atPath: atlas))
        #expect(app.scan.rows[.swiftpmBuilds]?.result == before)
    }
}
