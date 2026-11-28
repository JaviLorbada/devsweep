import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Kept folders")
struct KeptFoldersViewModelTests {
    let ferris = KeptFolder(
        path: "/Users/someone/Developer/ferris/target",
        repository: "/Users/someone/Developer/ferris/target/debug/zlib",
        kilobytes: 8192)
    let ledger = KeptFolder(
        path: "/Users/someone/Developer/Ledger/target",
        repository: "/Users/someone/Developer/Ledger/target",
        kilobytes: 1024)
    let marks = FakeMarking()

    var found: ItemResult {
        ItemResult(item: .cargoBuilds, paths: [], kilobytes: 0, location: "", kept: [self.ferris, self.ledger])
    }

    func kept(_ row: ScanRow) -> (KeptFoldersViewModel, FakeScanResults) {
        let scan = FakeScanResults()
        scan.tally = Tally(order: [row.item], rows: [row.item: row])
        return (KeptFoldersViewModel(scan: scan, marks: self.marks), scan)
    }

    @Test
    func `each kept folder goes by its project, with its size, its path and why it was kept`() {
        let (kept, _) = self.kept(ScanRow(item: .cargoBuilds, state: .measured, result: self.found))
        let lines = kept.lines(of: .cargoBuilds)
        #expect(lines.map(\.name) == ["ferris", "Ledger"])
        #expect(lines.map(\.size) == ["8 MB", "1 MB"])
        #expect(lines.map(\.path) == ["~/Developer/ferris/target", "~/Developer/Ledger/target"])
        #expect(lines.map(\.reason) == ["Holds a git repository, debug/zlib", "Is a git repository"])
        #expect(lines.map(\.part) == [.folder(self.ferris.path), .folder(self.ledger.path)])
        #expect(kept.lines(of: .nodeModules).isEmpty)
    }

    @Test
    func `the row warns of one kept folder by name, and of several by count`() {
        let (two, _) = self.kept(ScanRow(item: .cargoBuilds, state: .measured, result: self.found))
        #expect(two.warning(for: .cargoBuilds) == "2 folders have a git repository. Check them before you clean.")

        let one = ItemResult(item: .cargoBuilds, paths: [], kilobytes: 0, location: "", kept: [self.ferris])
        let (single, _) = self.kept(ScanRow(item: .cargoBuilds, state: .measured, result: one))
        #expect(single.warning(for: .cargoBuilds) == "ferris/target has a git repository. Check it before you clean.")

        let plain = result(.cargoBuilds, kilobytes: 4)
        let (none, _) = self.kept(ScanRow(item: .cargoBuilds, state: .measured, result: plain))
        #expect(none.warning(for: .cargoBuilds) == nil)
        let (measuring, _) = self.kept(ScanRow(item: .cargoBuilds, state: .measuring, previous: self.found))
        #expect(measuring.warning(for: .cargoBuilds) == nil)
    }

    @Test
    func `the last scan's show dimmed until this one measures them, and only this scan's can be ticked`() {
        let (measured, _) = self.kept(ScanRow(item: .cargoBuilds, state: .measured, result: self.found))
        #expect(measured.showsTicks(for: .cargoBuilds))

        let (waiting, _) = self.kept(ScanRow(item: .cargoBuilds, state: .waiting, previous: self.found))
        #expect(waiting.lines(of: .cargoBuilds).count == 2)
        #expect(!waiting.showsTicks(for: .cargoBuilds))

        let (measuring, _) = self.kept(ScanRow(item: .cargoBuilds, state: .measuring, previous: self.found))
        #expect(measuring.lines(of: .cargoBuilds).isEmpty)
    }

    @Test
    func `ticking one marks its folder to clean, and waits while a scan or a clean runs`() throws {
        let (kept, scan) = self.kept(ScanRow(item: .cargoBuilds, state: .measured, result: self.found))
        let line = try #require(kept.lines(of: .cargoBuilds).first)
        #expect(kept.canTick)
        #expect(!kept.isMarked(line, of: .cargoBuilds))

        kept.setMarked(line, of: .cargoBuilds, true)
        #expect(self.marks.markedParts(of: .cargoBuilds) == [.folder(self.ferris.path)])
        #expect(kept.isMarked(line, of: .cargoBuilds))
        kept.setMarked(line, of: .cargoBuilds, false)
        #expect(self.marks.markedParts(of: .cargoBuilds).isEmpty)

        scan.statusFacts.isScanning = true
        #expect(!kept.canTick)
        scan.statusFacts.isScanning = false
        scan.isCleaning = true
        #expect(!kept.canTick)
    }
}
