import DevSweepKit
import Testing
@testable import DevSweepApp

/// A clean from the question to the totals, with fakes for the rows, the
/// cleaner, the marks and the running apps: nothing touches the disk. The
/// flow tests clean real folders on a fake home.
@MainActor
@Suite("Cleaning")
struct CleaningModelTests {
    let rows = FakeScanRows([
        result(.derivedData, kilobytes: 64),
        result(.npmCache, kilobytes: 16),
        result(.homebrew, kilobytes: 0),
    ])
    let marks = FakeMarking()

    func cleaning(apps: FakeRunningApps = FakeRunningApps(), moveToTrash: Bool = true) -> CleaningModel {
        CleaningModel(scan: self.rows, marks: self.marks, apps: apps, moveToTrash: moveToTrash)
    }

    // MARK: What it asks

    @Test
    func `with Xcode open, DerivedData asks to quit it, and Quit and Clean cleans once it quits`() async throws {
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
        await waitUntil { self.rows.rows[.derivedData]?.state == .cleaned }
        #expect(self.rows.cleaner.cleaned == [.derivedData])
        #expect(!self.rows.isCleaning)
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
        #expect(CleanPrompt.title(for: pending, moveToTrash: false) == "Delete \(SizeText.of(kilobytes: 16)) for good?")
        #expect(self.rows.cleansBegun == 0, "nothing goes before the answer")
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

    // MARK: Cleaning

    @Test
    func `moving to the Trash cleans at once, counts for this session, and Put Back undoes it`() async {
        let cleaning = self.cleaning()
        await cleaning.requestClean([.npmCache])
        #expect(cleaning.pendingClean == nil, "the Trash needs no question")
        await waitUntil { self.rows.rows[.npmCache]?.state == .cleaned }
        #expect(self.rows.rows[.npmCache]?.canPutBack == true)
        #expect(cleaning.trashedThisSession == 16)
        #expect(cleaning.deletedThisSession == 0)
        #expect(self.marks.cleanedItems == [.npmCache])

        await cleaning.putBack(.npmCache)
        #expect(self.rows.cleaner.putBacks == 1)
        #expect(self.rows.rows[.npmCache]?.state == .measured)
        #expect(cleaning.trashedThisSession == 0)
        #expect(self.rows.cleansBegun == 2, "Put Back takes the rows too")
        #expect(!self.rows.isCleaning)
    }

    @Test
    func `deleting for good counts as deleted, and can't be put back`() async throws {
        let cleaning = self.cleaning(moveToTrash: false)
        await cleaning.requestClean([.npmCache])
        await waitUntil { cleaning.pendingClean != nil }
        try await cleaning.confirmClean(#require(cleaning.pendingClean))
        #expect(self.rows.rows[.npmCache]?.state == .cleaned)
        #expect(self.rows.rows[.npmCache]?.canPutBack == false)
        #expect(cleaning.deletedThisSession == 16)
        #expect(cleaning.trashedThisSession == 0)
    }

    @Test
    func `what can't be removed is left alone, and a notice says so`() async {
        let rows = FakeScanRows(
            [result(.npmCache, kilobytes: 16)],
            cleaner: FakeCleaner(failing: ["/Users/someone/npm-cache"]))
        let cleaning = CleaningModel(scan: rows, marks: self.marks, apps: FakeRunningApps(), moveToTrash: true)
        await cleaning.requestClean([.npmCache])
        await waitUntil { cleaning.notice != nil }
        #expect(cleaning.notice?.title == "Some things were left alone")
        #expect(rows.rows[.npmCache]?.state == .measured)
        #expect(cleaning.trashedThisSession == 0)
        #expect(self.marks.cleanedItems.isEmpty)
        #expect(rows.warnings == ["Couldn't remove /Users/someone/npm-cache."])
    }

    @Test
    func `Xcode opened after the question: its items are skipped, the rest cleaned`() async throws {
        let apps = FakeRunningApps()
        let cleaning = self.cleaning(apps: apps, moveToTrash: false)
        await cleaning.requestClean([.derivedData, .npmCache])
        await waitUntil { cleaning.pendingClean != nil }
        let confirm = try #require(cleaning.pendingClean)

        apps.running = [.xcode]
        await cleaning.confirmClean(confirm)
        #expect(self.rows.cleaner.cleaned == [.npmCache])
        #expect(self.rows.rows[.derivedData]?.state == .measured)
        #expect(cleaning.notice?.message.hasPrefix("Skipped ") == true)
        #expect(cleaning.notice?.message.hasSuffix("Xcode is open.") == true)
    }

    // MARK: Parts

    @Test
    func `parts that need Xcode closed ask to quit it; a project alone asks first while Xcode is open`() async throws {
        let derivedData = try #require(sampleResults.first { $0.item == .derivedData })
        let project = try #require(derivedData.derivedData?.projects.first).folder
        let rows = FakeScanRows([derivedData])
        self.marks.parts[.derivedData] = [.compilationCache, .folder(project)]
        let cleaning = CleaningModel(scan: rows, marks: self.marks, apps: FakeRunningApps([.xcode]), moveToTrash: true)

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
        #expect(confirm.kilobytes == derivedData.kilobytes(of: .folder(project)), "the project's size, not the item's")
        #expect(confirm.xcodeOpen)
        #expect(rows.cleansBegun == 0, "nothing goes before the answer")
    }

    @Test
    func `a project cleaned on its own leaves the rest, says what went, and Put Back restores it`() async throws {
        let before = try #require(sampleResults.first { $0.item == .derivedData })
        let project = try #require(before.derivedData?.projects.first).folder
        let rows = FakeScanRows([before])
        self.marks.parts[.derivedData] = [.folder(project)]
        let cleaning = CleaningModel(scan: rows, marks: self.marks, apps: FakeRunningApps(), moveToTrash: true)

        await cleaning.requestCleanParts(of: .derivedData)
        await waitUntil { cleaning.lastPartsClean(of: .derivedData) != nil }
        let clean = try #require(cleaning.lastPartsClean(of: .derivedData))
        let projectKilobytes = before.kilobytes(of: .folder(project))
        #expect(clean.summary == "1 project")
        #expect(clean.kilobytes == projectKilobytes)
        #expect(rows.rows[.derivedData]?.result?.kilobytes == before.kilobytes - projectKilobytes)
        #expect(self.marks.markedParts(of: .derivedData).isEmpty)
        #expect(cleaning.trashedThisSession == projectKilobytes)

        await cleaning.putBackParts(of: .derivedData)
        #expect(rows.rows[.derivedData]?.result == before)
        #expect(cleaning.lastPartsClean(of: .derivedData) == nil)
        #expect(cleaning.trashedThisSession == 0)
    }
}
