import Foundation
import Testing
@testable import DevCleanKit

@Suite("Saved scans")
struct SavedScanTests {
    func sample(home: String) -> SavedScan {
        let breakdown = DerivedDataBreakdown(compilationCacheKilobytes: 10, moduleCacheKilobytes: 2, otherKilobytes: 1, projects: [
            DerivedDataProject(name: "A/A", status: .built("2026-10-20"), kilobytes: 5, folder: "/dd/A", workspacePath: "/w/A"),
            DerivedDataProject(name: "B/B", status: .gone, kilobytes: 3, folder: "/dd/B", workspacePath: "/w/B"),
        ])
        return SavedScan(
            date: Date(timeIntervalSince1970: 1_792_000_000),
            home: home,
            results: [
                ItemResult(item: .derivedData, paths: ["\(home)/dd"], kilobytes: 21, location: "~/dd", derivedData: breakdown),
                ItemResult(item: .homebrew, paths: [], kilobytes: 0, location: "brew cleanup --prune=all", sizeKnown: false),
            ],
            extras: Extras(
                xcodes: [InstalledXcode(path: "/Applications/Xcode.app", version: "27.2", build: "27B48", kilobytes: 9,
                                        lastOpened: Date(timeIntervalSince1970: 1_791_000_000), isSelected: true)],
                runtimes: [SimulatorRuntime(id: "R", identifier: "i", platform: "iOS", version: "27.1", build: "b", kilobytes: 7,
                                            lastUsedDay: nil, daysSinceUsed: nil, simulatorCount: 0)]
            )
        )
    }

    @Test
    func `A saved scan comes back as it was, for the same home`() throws {
        let home = FakeHome()
        let store = ScanStore.standard(home: home.home)
        #expect(store.url.path(percentEncoded: false).hasSuffix("/Library/Application Support/DevClean/last-scan.json"))
        #expect(store.load(home: home.home) == nil)
        try store.save(sample(home: home.home))
        #expect(store.load(home: home.home) == sample(home: home.home))
    }

    @Test
    func `A scan of another folder, another version or a broken file is ignored`() throws {
        let home = FakeHome()
        let store = ScanStore.standard(home: home.home)
        try store.save(sample(home: "/somewhere/else"))
        #expect(store.load(home: home.home) == nil)

        var old = sample(home: home.home)
        old.version = 0
        try store.save(old)
        #expect(store.load(home: home.home) == nil)

        try Data("{ not json".utf8).write(to: store.url)
        #expect(store.load(home: home.home) == nil)
    }
}
