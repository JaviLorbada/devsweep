import Foundation
import Synchronization
import Testing
@testable import DevCleanKit

/// The disk as it is, except that removing is only written down.
final class RecordingFileSystem: FileSystemAccess {
    let removed = Mutex<[String]>([])
    private let disk = LiveFileSystem()

    func childNames(_ directory: String) -> [String] { disk.childNames(directory) }
    func isDirectory(_ path: String) -> Bool { disk.isDirectory(path) }
    func isSymlink(_ path: String) -> Bool { disk.isSymlink(path) }
    func exists(_ path: String) -> Bool { disk.exists(path) }
    func modificationTime(_ path: String) -> Int { disk.modificationTime(path) }
    func contents(of path: String) -> Data? { disk.contents(of: path) }
    func remove(_ path: String) throws { removed.withLock { $0.append(path) } }
}

struct FixedClock: WallClock {
    let date: Date
    func now() -> Date { date }
}

@Suite("Dependencies")
struct DependenciesTests {
    @Test
    func `deleting goes through the dependencies' file system`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path("Library/Caches/org.swift.swiftpm"))
        let files = RecordingFileSystem()
        let config = ScanConfig.fromEnvironment(home.environment)
        let engine = try Engine(config: config, dependencies: Dependencies(tools: tools.tools, files: files))
        let result = try #require(await collect(engine).result(.swiftpmCache))

        let outcome = await engine.clean(result, mode: .delete)
        #expect(outcome.removed.map(\.original) == result.paths)
        #expect(files.removed.withLock { $0 } == result.paths)
        #expect(FileManager.default.fileExists(atPath: home.path("Library/Caches/org.swift.swiftpm")), "the fake removed nothing")
    }

    @Test
    func `how long a runtime has gone unused is counted from the dependencies' clock`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.stubRuntimes()
        let later = Date().addingTimeInterval(400 * 86_400)
        let config = ScanConfig.fromEnvironment(home.environment)
        let engine = try Engine(config: config, dependencies: Dependencies(tools: tools.tools, clock: FixedClock(date: later)))
        let runtimes = await engine.extras().runtimes
        let current = try #require(runtimes.first { $0.version == "27.0" })
        #expect(current.daysSinceUsed ?? 0 >= 399)
    }
}
