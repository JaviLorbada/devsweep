import DevSweepKit
import Testing
@testable import DevSweepApp

/// What a clean asks, and when it goes ahead, with fakes for the rows, the
/// marks and the running apps. The fake rows never let a clean begin, so
/// nothing is cleaned here; the flow tests clean for real, on a fake home.
@MainActor
@Suite("Cleaning")
struct CleaningModelTests {
    let rows = FakeCleaningRows([
        result(.derivedData, kilobytes: 64),
        result(.npmCache, kilobytes: 16),
        result(.homebrew, kilobytes: 0),
    ])
    let marks = FakeMarking()

    func cleaning(apps: FakeRunningApps = FakeRunningApps(), moveToTrash: Bool = true) -> CleaningModel {
        CleaningModel(scan: self.rows, marks: self.marks, apps: apps, moveToTrash: moveToTrash)
    }

    @Test
    func `with Xcode open, DerivedData asks to quit it, and Quit and Clean goes ahead once it quits`() async throws {
        let apps = FakeRunningApps([.xcode])
        let cleaning = self.cleaning(apps: apps)
        await cleaning.requestClean([.derivedData])
        let pending = try #require(cleaning.pendingClean)
        guard case .quitApps([.xcode]) = pending.stage else {
            Issue.record("expected to be asked to quit Xcode")
            return
        }
        #expect(self.rows.cleansBegun == 0, "nothing goes before the answer")

        await cleaning.quitAppsAndClean(pending)
        #expect(apps.askedToQuit == [[.xcode]])
        #expect(cleaning.pendingClean == nil)
        await waitUntil { self.rows.cleansBegun == 1 }
        #expect(self.rows.cleansBegun == 1)
    }

    @Test
    func `when Xcode won't quit, nothing is cleaned and a notice says so`() async throws {
        let cleaning = self.cleaning(apps: FakeRunningApps([.xcode], quits: false))
        await cleaning.requestClean([.derivedData])
        let pending = try #require(cleaning.pendingClean)
        await cleaning.quitAppsAndClean(pending)
        #expect(cleaning.notice?.title == "Xcode didn't quit")
        #expect(cleaning.pendingClean == nil)
        #expect(self.rows.cleansBegun == 0)
    }

    @Test
    func `with nothing open, moving to the Trash goes ahead without a question`() async {
        let cleaning = self.cleaning()
        await cleaning.requestClean([.derivedData, .npmCache])
        #expect(cleaning.pendingClean == nil)
        await waitUntil { self.rows.cleansBegun == 1 }
        #expect(self.rows.cleansBegun == 1)
    }

    @Test
    func `deleting for good, and what simctl or brew removes, asks first`() async throws {
        let cleaning = self.cleaning()
        #expect(!cleaning.needsConfirmation([.npmCache, .derivedData]))
        #expect(cleaning.needsConfirmation([.npmCache, .homebrew]))
        #expect(cleaning.needsConfirmation([.simulators]))
        cleaning.moveToTrash = false
        #expect(cleaning.needsConfirmation([.npmCache]))

        await cleaning.requestClean([.npmCache])
        await waitUntil { cleaning.pendingClean != nil }
        let pending = try #require(cleaning.pendingClean)
        guard case .confirm = pending.stage else {
            Issue.record("expected to be asked to confirm")
            return
        }
        #expect(self.rows.cleansBegun == 0, "nothing goes before the answer")
        await cleaning.confirmClean(pending)
        #expect(self.rows.cleansBegun == 1)
    }

    @Test
    func `nothing is asked or cleaned while scanning, or for what has nothing to clean`() async {
        let cleaning = self.cleaning(apps: FakeRunningApps([.xcode]))
        self.rows.isScanning = true
        await cleaning.requestClean([.derivedData])
        #expect(cleaning.pendingClean == nil)

        self.rows.isScanning = false
        await cleaning.requestClean([.homebrew, .simulators])
        #expect(cleaning.pendingClean == nil)
        #expect(self.rows.cleansBegun == 0)
    }

    @Test
    func `Clean the Others goes on with what can go while Xcode is open`() async throws {
        let cleaning = self.cleaning(apps: FakeRunningApps([.xcode]), moveToTrash: false)
        await cleaning.requestClean([.derivedData, .npmCache])
        let quit = try #require(cleaning.pendingClean)
        #expect(quit.hasOthers)

        cleaning.cleanSkippingXcodeItems(quit)
        await waitUntil { cleaning.pendingClean != nil }
        let confirm = try #require(cleaning.pendingClean)
        #expect(confirm.items == [.npmCache])
    }

    @Test
    func `parts that need Xcode closed ask to quit it; a project alone asks first while Xcode is open`() async throws {
        let derivedData = try #require(sampleResults.first { $0.item == .derivedData })
        let project = try #require(derivedData.derivedData?.projects.first).folder
        let rows = FakeCleaningRows([derivedData])
        let marks = FakeMarking()
        marks.parts[.derivedData] = [.compilationCache, .folder(project)]
        let cleaning = CleaningModel(scan: rows, marks: marks, apps: FakeRunningApps([.xcode]), moveToTrash: true)

        await cleaning.requestCleanParts(of: .derivedData)
        let quit = try #require(cleaning.pendingClean)
        guard case .quitApps([.xcode]) = quit.stage else {
            Issue.record("expected to be asked to quit Xcode")
            return
        }
        #expect(quit.hasOthers)

        cleaning.cleanSkippingXcodeItems(quit)
        await waitUntil { cleaning.pendingClean != nil }
        let confirm = try #require(cleaning.pendingClean)
        #expect(confirm.parts == [.folder(project)])
        #expect(confirm.xcodeOpen)
        #expect(rows.cleansBegun == 0, "nothing goes before the answer")
    }
}
