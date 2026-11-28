import DevSweepKit
import Testing
@testable import DevSweepApp

@Suite("Kept folder copy")
struct KeptFolderCopyTests {
    @Test
    func `a kept folder says where its repository sits, or that it is one`() {
        let folder = "/Users/someone/Developer/dashboard/node_modules"
        #expect(KeptFolder(path: folder, repository: "\(folder)/chart-kit", kilobytes: 2048).reason
            == "Holds a git repository, chart-kit")
        #expect(KeptFolder(path: folder, repository: folder, kilobytes: 2048).reason == "Is a git repository")
        #expect(KeptFolder(path: folder, repository: folder, kilobytes: 2048).keptBecause == "is a git repository")
    }
}
