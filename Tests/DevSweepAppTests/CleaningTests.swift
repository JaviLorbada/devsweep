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
