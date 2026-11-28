import DevSweepKit
import Testing
@testable import DevSweepApp

@Suite("Clean prompt")
struct CleanPromptTests {
    let derivedData = ItemResult(
        item: .derivedData,
        paths: ["/dd"],
        kilobytes: 1000,
        location: "~/dd",
        derivedData: DerivedDataBreakdown(
            compilationCacheKilobytes: 400,
            moduleCacheKilobytes: 50,
            otherKilobytes: 10,
            projects: [
                Self.project("Atlas", 300),
                Self.project("Kite", 200),
                Self.project("Orbit", 30),
                Self.project("Vega", 10),
            ]))
    let builds = ItemResult(
        item: .swiftpmBuilds,
        paths: ["/code/A/.build", "/code/B/.build", "/code/C/.build", "/code/D/.build"],
        kilobytes: 100,
        location: "~/code",
        folderKilobytes: ["/code/A/.build": 40, "/code/B/.build": 30, "/code/C/.build": 20, "/code/D/.build": 10])

    static func project(_ name: String, _ kilobytes: Int64) -> DerivedDataProject {
        DerivedDataProject(
            name: "\(name)/\(name)",
            status: .built("2026-11-14"),
            kilobytes: kilobytes,
            folder: "/dd/\(name)-abc",
            workspacePath: "/code/\(name)/\(name).xcodeproj")
    }

    func question(_ parts: Set<ItemPart>, in result: ItemResult, xcodeOpen: Bool = false) -> PendingClean {
        CleanPrompt.partsQuestion(parts, of: result.item, in: result, xcodeOpen: xcodeOpen, stage: .confirm)
    }

    @Test
    func `projects of DerivedData are named up to three, and counted past that`() {
        let two = self.question([.folder("/dd/Kite-abc"), .folder("/dd/Atlas-abc")], in: self.derivedData)
        #expect(two.partsSubject == "DerivedData for Atlas and Kite")
        #expect(!two.partsPlural)

        let projects = self.derivedData.derivedData?.projects.map { ItemPart.folder($0.folder) } ?? []
        let all = self.question(Set(projects), in: self.derivedData)
        #expect(all.partsSubject == "DerivedData for 4 projects")
        #expect(!all.partsPlural)
    }

    @Test
    func `other parts are named up to three, largest first, with those that need Xcode closed`() {
        let pending = self.question([.folder("/dd/Kite-abc"), .compilationCache], in: self.derivedData)
        #expect(pending.partsSubject == "the compilation cache and DerivedData for Kite")
        #expect(pending.partsPlural)
        #expect(pending.blockedPartNames == ["the compilation cache"])
        #expect(pending.kilobytes == 600)
        #expect(pending.xcodeName.isEmpty)
    }

    @Test
    func `past three, parts are counted by what the item's folders are called`() {
        let caches = self.question(
            [.compilationCache, .moduleCache, .other, .folder("/dd/Atlas-abc")],
            in: self.derivedData)
        #expect(caches.partsSubject == "4 parts of DerivedData")
        #expect(caches.partsPlural)

        let folders = self.question(Set(self.builds.paths.map(ItemPart.folder)), in: self.builds)
        #expect(folders.partsSubject == "4 .build folders")
        #expect(folders.partsPlural)
        #expect(folders.kilobytes == 100)
    }

    @Test
    func `a question names the kept folders it takes, ticked or whole, with their repositories`() {
        let kept = [
            KeptFolder(path: "/code/E/.build", repository: "/code/E/.build/Tool", kilobytes: 50),
            KeptFolder(path: "/code/F/.build", repository: "/code/F/.build", kilobytes: 5),
        ]
        let builds = ItemResult(
            item: .swiftpmBuilds,
            paths: ["/code/A/.build", "/code/E/.build", "/code/F/.build"],
            kilobytes: 95,
            location: "~/code",
            folderKilobytes: ["/code/A/.build": 40, "/code/E/.build": 50, "/code/F/.build": 5],
            kept: kept)
        let one = self.question([.folder("/code/A/.build"), .folder("/code/E/.build")], in: builds)
        #expect(one.kilobytes == 90)
        #expect(one.keptNote == "E/.build holds a git repository, Tool: its edits and commits go too.")
        #expect(CleanPrompt.message(for: one, moveToTrash: true) == "E/.build and A/.build go to the Trash, so they "
            + "can be put back. E/.build holds a git repository, Tool: its edits and commits go too.")
        let both = self.question(Set(kept.map { .folder($0.path) }), in: builds)
        #expect(both.keptNote == "2 folders hold a git repository: their edits and commits go too.")
        #expect(self.question([.folder("/code/A/.build")], in: builds).keptNote.isEmpty)

        let whole = PendingClean(items: [.swiftpmBuilds], stage: .confirm, rows: measuredRows([builds]))
        #expect(whole.kilobytes == 95)
        #expect(CleanPrompt.message(for: whole, moveToTrash: true) == "Everything moves to the Trash, so it can be "
            + "put back. 2 folders hold a git repository: their edits and commits go too.")
    }

    @Test
    func `one project is the one to close, when Xcode is open and builds into it`() {
        let project = self.question([.folder("/dd/Atlas-abc")], in: self.derivedData, xcodeOpen: true)
        #expect(project.partsSubject == "DerivedData for Atlas")
        #expect(project.xcodeOpen)
        #expect(project.xcodeName == "Atlas")
        #expect(project.kilobytes == 300)

        let folder = self.question([.folder("/code/A/.build")], in: self.builds, xcodeOpen: true)
        #expect(folder.partsSubject == "A/.build")
        #expect(!folder.xcodeOpen)
    }

    @Test
    func `without the scan's result, the question names nothing`() {
        let pending = CleanPrompt.partsQuestion(
            [.compilationCache],
            of: .derivedData,
            in: nil,
            xcodeOpen: true,
            stage: .confirm)
        #expect(pending.parts == [.compilationCache])
        #expect(pending.partsSubject.isEmpty)
        #expect(pending.kilobytes == 0)
        #expect(!pending.xcodeOpen)
    }
}
