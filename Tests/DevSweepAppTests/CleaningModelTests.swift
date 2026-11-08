import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Cleaning whole items")
struct CleaningModelTests {
    @Test
    func `with Xcode open, DerivedData asks to quit it, then Quit and Clean quits it and cleans`() async throws {
        let home = TemporaryHome()
        let folder = "\(home.path)/Library/Developer/Xcode/DerivedData/Atlas-abc"
        write(64, to: folder)
        let apps = FakeDeveloperApps(running: [.xcode])
        let model = await scannedModel(home: home, apps: apps)
        let kilobytes = try #require(model.scan.rows[.derivedData]?.kilobytes)

        await model.cleaning.requestClean([.derivedData])
        let pending = try #require(model.cleaning.pendingClean)
        guard case .quitApps([.xcode]) = pending.stage else {
            Issue.record("expected to be asked to quit Xcode")
            return
        }
        #expect(FileManager.default.fileExists(atPath: folder), "nothing goes before the answer")

        await model.cleaning.quitAppsAndClean(pending)
        await waitUntil { model.scan.rows[.derivedData]?.state == .cleaned }
        #expect(apps.asked == [[.xcode]])
        #expect(model.scan.rows[.derivedData]?.state == .cleaned)
        #expect(!FileManager.default.fileExists(atPath: folder))
        #expect(model.cleaning.trashedThisSession == kilobytes)
        #expect(!model.marks.marked.contains(.derivedData))
    }

    @Test
    func `when Xcode won't quit, nothing is cleaned and a notice says so`() async throws {
        let home = TemporaryHome()
        let folder = "\(home.path)/Library/Developer/Xcode/DerivedData/Atlas-abc"
        write(64, to: folder)
        let model = await scannedModel(home: home, apps: FakeDeveloperApps(running: [.xcode], quits: false))

        await model.cleaning.requestClean([.derivedData])
        let pending = try #require(model.cleaning.pendingClean)
        await model.cleaning.quitAppsAndClean(pending)

        #expect(model.cleaning.notice?.title == "Xcode didn't quit")
        #expect(model.cleaning.pendingClean == nil)
        #expect(model.scan.rows[.derivedData]?.state == .measured)
        #expect(FileManager.default.fileExists(atPath: folder))
    }

    @Test
    func `moving to the Trash cleans at once, and Put Back brings the whole item back`() async throws {
        let home = TemporaryHome()
        let folder = "\(home.path)/.npm/_cacache"
        write(64, to: folder)
        let model = await scannedModel(home: home)
        let kilobytes = try #require(model.scan.rows[.npmCache]?.kilobytes)

        await model.cleaning.requestClean([.npmCache])
        await waitUntil { model.scan.rows[.npmCache]?.state == .cleaned }
        #expect(model.cleaning.pendingClean == nil, "the Trash needs no question")
        #expect(!FileManager.default.fileExists(atPath: folder))
        #expect(model.scan.rows[.npmCache]?.canPutBack == true)
        #expect(model.cleaning.trashedThisSession == kilobytes)
        #expect(model.statusLine.contains("moved to Trash this session"))

        await model.cleaning.putBack(.npmCache)
        #expect(FileManager.default.fileExists(atPath: folder))
        #expect(model.scan.rows[.npmCache]?.state == .measured)
        #expect(model.cleaning.trashedThisSession == 0)
    }

    @Test
    func `deleting for good, and what simctl or brew removes, asks first`() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        #expect(model.cleaning.moveToTrash)
        #expect(!model.cleaning.needsConfirmation([.npmCache, .derivedData]))
        #expect(model.cleaning.needsConfirmation([.npmCache, .homebrew]))
        #expect(model.cleaning.needsConfirmation([.simulators]))
        model.cleaning.moveToTrash = false
        #expect(model.cleaning.needsConfirmation([.npmCache]))
    }
}
