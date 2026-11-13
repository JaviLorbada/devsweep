import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Inspector")
struct InspectorTests {
    @Test
    func `DerivedData projects go by the folder they live in`() {
        func project(_ name: String) -> DerivedDataProject {
            DerivedDataProject(
                name: name,
                status: .built("2026-10-20"),
                kilobytes: 1,
                folder: "\(name)-abcdefghijklmnop",
                workspacePath: "/Users/someone/Developer/\(name).xcworkspace")
        }
        #expect(DerivedDataParts.displayName(project("atlas-2/Atlas")) == "atlas-2")
        #expect(DerivedDataParts.displayName(project("Atlas-iOS/Atlas")) == "Atlas-iOS")
        #expect(DerivedDataParts.displayName(project("Atlas/Atlas")) == "Atlas")
        #expect(DerivedDataParts.displayName(project("/Loose")) == "Loose")
    }

    @Test
    func `folders that share a name are told apart by the one above`() {
        let names = PartsList.folderNames(["/w/a/Atlas/.build", "/w/b/Atlas/.build", "/w/kite-1/.build"])
        #expect(names == ["/w/a/Atlas/.build": "a/Atlas", "/w/b/Atlas/.build": "b/Atlas", "/w/kite-1/.build": "kite-1"])
    }

    @Test
    func `a runtime's size says what is the runtime and what its download, which removing it takes too`() {
        func runtime(download: Int64?) -> SimulatorRuntime {
            SimulatorRuntime(
                id: "A",
                identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-5",
                platform: "iOS",
                version: "18.5",
                build: "22F77",
                kilobytes: 8_007_813 + (download ?? 0),
                lastUsedDay: nil,
                daysSinceUsed: nil,
                simulatorCount: 0,
                downloadKilobytes: download)
        }
        let downloaded = runtime(download: 8_886_719)
        #expect(SizeText.of(kilobytes: downloaded.kilobytes) == "17.3 GB")
        #expect(RuntimeWords.parts(downloaded) == "8.2 GB runtime and 9.1 GB download")
        #expect(RuntimeWords.size(downloaded) == "8.2 GB is the runtime, and 9.1 GB a download macOS keeps for it "
            + "in /System/Library/AssetsV2, which simctl leaves out of its size. Removing the runtime removes both.")
        #expect(RuntimeWords.parts(runtime(download: nil)) == nil)
        #expect(RuntimeWords.size(runtime(download: nil)) == nil)
    }

    @Test
    func `the projects summed in one line come last, however large`() {
        let lines = PartsList.ordered([
            .init(id: "Ledger", name: "Ledger", kilobytes: 2048, part: .folder("Ledger")),
            .init(id: "rest", name: "2 more projects", kilobytes: 3072),
            .init(id: "cache", name: "Shared compilation cache", kilobytes: 47104, part: .compilationCache),
            .init(id: "Atlas", name: "Atlas", kilobytes: 25600, part: .folder("Atlas")),
        ])
        #expect(lines.map(\.id) == ["cache", "Atlas", "Ledger", "rest"])
    }
}
