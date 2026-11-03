import Darwin
import Foundation
import Synchronization
import Testing
@testable import DevSweepKit

@Suite("Deleting a folder")
struct TreeRemoverTests {
    /// What `du` counts for the files under `path`, in bytes: their
    /// allocated blocks, which the removal reports as it goes.
    func allocatedBytes(under path: String) -> Int64 {
        var bytes: Int64 = 0
        FileTree.walk(path) { entry in
            if entry.kind == .other, let status = entry.status {
                bytes += Int64(status.st_blocks) * 512
            }
            return .proceed
        }
        return bytes
    }

    @Test
    func `removes nested folders, hidden files and a folder of more files than one thread takes`() {
        let home = FakeHome()
        let tree = home.outside("DerivedData")
        home.writeZeros("\(tree)/Project-abc/Build/Intermediates.noindex/App.build/File.o", kilobytes: 64)
        home.write("\(tree)/.hidden", "x")
        home.mkdir("\(tree)/Empty/Inside")
        // Three threads' worth of files in one folder, like the compilation cache.
        for index in 0..<1300 {
            home.write("\(tree)/CompilationCache.noindex/generic/v1.1/\(index)", "blob \(index)")
        }
        let expected = self.allocatedBytes(under: tree)
        let reported = Mutex<Int64>(0)

        #expect(TreeRemover.remove(tree) { bytes in reported.withLock { $0 = max($0, bytes) } })
        #expect(!home.exists(tree))
        #expect(home.exists(home.outside("")), "the folder above stays")
        #expect(reported.withLock { $0 } == expected)
    }

    @Test
    func `removes a symlink inside without following it`() {
        let home = FakeHome()
        let tree = home.outside("cache")
        let target = home.fill(home.outside("elsewhere"))
        home.fill("\(tree)/real")
        home.symlink(target, at: "\(tree)/real/to-folder")
        home.symlink("\(target)/file", at: "\(tree)/to-file")

        #expect(TreeRemover.remove(tree))
        #expect(!home.exists(tree))
        #expect(home.isFile("\(target)/file"))
    }

    @Test
    func `a folder that is itself a symlink goes as a link, and what it points to stays`() {
        let home = FakeHome()
        let target = home.fill(home.outside("elsewhere"))
        let link = home.outside("link")
        home.symlink(target, at: link)

        #expect(TreeRemover.remove(link))
        #expect(!home.exists(link))
        #expect(home.isFile("\(target)/file"))
    }

    @Test
    func `a file goes too`() {
        let home = FakeHome()
        let file = home.outside("file")
        home.write(file, "data")

        #expect(TreeRemover.remove(file))
        #expect(!home.exists(file))
    }

    @Test
    func `says so when it can't remove everything, and leaves the rest`() throws {
        let home = FakeHome()
        let tree = home.outside("cache")
        home.fill("\(tree)/open")
        let locked = home.fill("\(tree)/locked")
        chmod(locked, 0o555)
        defer { chmod(locked, 0o755) }

        #expect(!TreeRemover.remove(tree))
        #expect(home.isFile("\(locked)/file"))
        #expect(!home.exists("\(tree)/open"))
        // FileManager can't either, and says why.
        #expect(throws: (any Error).self) { try LiveFileSystem().remove(tree) { _ in } }
    }

    @Test
    func `cleaning reports the bytes deleted across an item's folders, never going back`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.writeZeros(home.path("Library/Caches/CocoaPods/a"), kilobytes: 256)
        home.writeZeros(home.path("Library/Caches/Sourcery/b"), kilobytes: 128)
        let expected = self.allocatedBytes(under: home.path("Library/Caches"))
        let engine = try engine(home, tools)
        let result = try #require(await collect(engine).result(.toolCaches))
        let reports = Mutex<[Int64]>([])

        let outcome = await engine.clean(result, mode: .delete) { bytes in reports.withLock { $0.append(bytes) } }
        #expect(outcome.removed.count == 2)
        let seen = reports.withLock { $0 }
        #expect(seen.last == expected)
        #expect(seen == seen.sorted())
    }
}
