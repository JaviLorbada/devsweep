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

@MainActor
@Suite("Cleaning")
struct CleaningTests {
    @Test
    func `while deleting, the row counts down what is left and Scan Again waits`() async throws {
        let home = TemporaryHome()
        write(64, to: "\(home.path)/.npm/_cacache")
        let files = HeldDelete()
        defer { files.letGo() }
        let model = AppModel(
            environment: ["HOME": home.path, "DEVSWEEP_PROJECT_DIRS": ""],
            store: InMemoryScanStore(),
            preferences: Preferences(storage: InMemoryPreferencesStore()),
            notifier: SilentNotificationPoster(),
            dependencies: Dependencies(tools: .unavailable, files: files))
        await finishScan(model)
        #expect(model.canScanOrStop)
        let kilobytes = try #require(model.rows[.npmCache]?.kilobytes)

        model.moveToTrash = false
        await model.requestClean([.npmCache])
        for _ in 0..<100 where model.pendingClean == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let pending = try #require(model.pendingClean)
        let cleaning = Task { await model.confirmClean(pending) }
        for _ in 0..<200 where (model.rows[.npmCache]?.removedBytes ?? 0) == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(model.isCleaning)
        #expect(!model.canScanOrStop)
        model.scan()
        #expect(!model.isScanning, "a scan waits for the clean")
        let row = try #require(model.rows[.npmCache])
        #expect(row.leftKilobytes == kilobytes - 32)
        #expect(row.cleaningProgress == Double(32) / Double(kilobytes))

        files.letGo()
        await cleaning.value
        #expect(model.canScanOrStop)
        #expect(model.rows[.npmCache]?.state == .cleaned)
        #expect(model.rows[.npmCache]?.cleaningProgress == nil)
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
@Suite("Cleaning parts of DerivedData")
struct PartsCleaningTests {
    /// A model that has scanned a DerivedData folder with the compilation
    /// cache and two projects, moving things to a Trash folder in the temp home.
    func scanned(_ home: TemporaryHome, runningApps: any RunningAppsChecking = NothingRunning()) async -> AppModel {
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
        let model = AppModel(
            environment: ["HOME": home.path, "DEVSWEEP_PROJECT_DIRS": ""],
            store: InMemoryScanStore(),
            preferences: Preferences(storage: InMemoryPreferencesStore()),
            notifier: SilentNotificationPoster(),
            dependencies: Dependencies(tools: tools))
        await finishScan(model)
        return model
    }

    func project(_ name: String, in model: AppModel) throws -> String {
        try #require(model.rows[.derivedData]?.result?.derivedData?.projects.first {
            $0.folder.hasSuffix("/\(name)-abc")
        }).folder
    }

    @Test
    func `ticking a project cleans just it, says so, and Put Back brings it back`() async throws {
        let home = TemporaryHome()
        let model = await scanned(home)
        let atlas = try project("Atlas", in: model)
        let before = try #require(model.rows[.derivedData]?.result)
        let atlasKilobytes = before.kilobytes(of: .folder(atlas))
        #expect(model.moveToTrash)

        model.setMarked(.folder(atlas), of: .derivedData, true)
        #expect(model.kilobytes(of: model.markedParts(of: .derivedData), in: .derivedData) == atlasKilobytes)
        await model.requestCleanParts(of: .derivedData)
        for _ in 0..<200 where model.lastPartsClean(of: .derivedData) == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }

        let clean = try #require(model.lastPartsClean(of: .derivedData))
        #expect(clean.summary == "1 project")
        #expect(clean.canPutBack)
        #expect(!FileManager.default.fileExists(atPath: atlas))
        #expect(try FileManager.default.fileExists(atPath: self.project("Fieldwork", in: model)))
        let left = try #require(model.rows[.derivedData]?.result)
        #expect(left.kilobytes == before.kilobytes - atlasKilobytes)
        #expect(left.derivedData?.projects.count == 1)
        #expect(model.rows[.derivedData]?.state == .measured)
        #expect(model.markedParts(of: .derivedData).isEmpty)
        #expect(model.trashedThisSession == atlasKilobytes)

        await model.putBackParts(of: .derivedData)
        #expect(FileManager.default.fileExists(atPath: atlas))
        #expect(model.rows[.derivedData]?.result == before)
        #expect(model.lastPartsClean(of: .derivedData) == nil)
        #expect(model.trashedThisSession == 0)
    }

    @Test
    func `the shared cache asks to quit Xcode, and a project alone asks first while Xcode is open`() async throws {
        let home = TemporaryHome()
        let model = await scanned(home, runningApps: XcodeOpen())
        let atlas = try project("Atlas", in: model)

        model.setMarked(.compilationCache, of: .derivedData, true)
        model.setMarked(.folder(atlas), of: .derivedData, true)
        await model.requestCleanParts(of: .derivedData)
        let quit = try #require(model.pendingClean)
        guard case .quitApps([.xcode]) = quit.stage else {
            Issue.record("expected to be asked to quit Xcode")
            return
        }
        #expect(quit.hasOthers)
        #expect(CleanPrompt.message(for: quit, moveToTrash: true).hasPrefix(
            "The compilation cache can't be cleaned while Xcode is open."))

        // Clean the Others: the project, once asked again with Xcode open.
        model.cleanSkippingXcodeItems(quit)
        for _ in 0..<100 where model.pendingClean == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let confirm = try #require(model.pendingClean)
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
        let model = AppModel(
            environment: ["HOME": home.path, "DEVSWEEP_PROJECT_DIRS": projects],
            store: InMemoryScanStore(),
            preferences: Preferences(storage: InMemoryPreferencesStore()),
            notifier: SilentNotificationPoster(),
            dependencies: Dependencies(tools: tools))
        await finishScan(model)
        let before = try #require(model.rows[.swiftpmBuilds]?.result)
        #expect(PartsList.listsFolders(before))
        let atlas = try #require(before.paths.first { $0.hasSuffix("/Atlas/.build") })
        #expect(PartsList.folderNames(before.paths)[atlas] == "Atlas")

        model.setMarked(.folder(atlas), of: .swiftpmBuilds, true)
        #expect(AppModel.summary(of: model.markedParts(of: .swiftpmBuilds), in: .swiftpmBuilds) == "1 folder")
        await model.requestCleanParts(of: .swiftpmBuilds)
        for _ in 0..<200 where model.lastPartsClean(of: .swiftpmBuilds) == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(!FileManager.default.fileExists(atPath: atlas))
        let left = try #require(model.rows[.swiftpmBuilds]?.result)
        #expect(left.paths.count == 1)
        #expect(left.label == "SwiftPM .build folders (1)")
        #expect(left.kilobytes == before.kilobytes - before.kilobytes(of: .folder(atlas)))

        await model.putBackParts(of: .swiftpmBuilds)
        #expect(FileManager.default.fileExists(atPath: atlas))
        #expect(model.rows[.swiftpmBuilds]?.result == before)
    }

    @Test
    func `folders that share a name are told apart by the one above`() {
        let names = PartsList.folderNames(["/w/a/Atlas/.build", "/w/b/Atlas/.build", "/w/kite-1/.build"])
        #expect(names == ["/w/a/Atlas/.build": "a/Atlas", "/w/b/Atlas/.build": "b/Atlas", "/w/kite-1/.build": "kite-1"])
    }
}
