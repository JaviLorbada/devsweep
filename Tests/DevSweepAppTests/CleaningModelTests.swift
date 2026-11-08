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
        let kilobytes = try #require(model.rows[.derivedData]?.kilobytes)

        await model.requestClean([.derivedData])
        let pending = try #require(model.pendingClean)
        guard case .quitApps([.xcode]) = pending.stage else {
            Issue.record("expected to be asked to quit Xcode")
            return
        }
        #expect(FileManager.default.fileExists(atPath: folder), "nothing goes before the answer")

        await model.quitAppsAndClean(pending)
        await waitUntil { model.rows[.derivedData]?.state == .cleaned }
        #expect(apps.asked == [[.xcode]])
        #expect(model.rows[.derivedData]?.state == .cleaned)
        #expect(!FileManager.default.fileExists(atPath: folder))
        #expect(model.trashedThisSession == kilobytes)
        #expect(!model.marked.contains(.derivedData))
    }

    @Test
    func `when Xcode won't quit, nothing is cleaned and a notice says so`() async throws {
        let home = TemporaryHome()
        let folder = "\(home.path)/Library/Developer/Xcode/DerivedData/Atlas-abc"
        write(64, to: folder)
        let model = await scannedModel(home: home, apps: FakeDeveloperApps(running: [.xcode], quits: false))

        await model.requestClean([.derivedData])
        let pending = try #require(model.pendingClean)
        await model.quitAppsAndClean(pending)

        #expect(model.notice?.title == "Xcode didn't quit")
        #expect(model.pendingClean == nil)
        #expect(model.rows[.derivedData]?.state == .measured)
        #expect(FileManager.default.fileExists(atPath: folder))
    }

    @Test
    func `moving to the Trash cleans at once, and Put Back brings the whole item back`() async throws {
        let home = TemporaryHome()
        let folder = "\(home.path)/.npm/_cacache"
        write(64, to: folder)
        let model = await scannedModel(home: home)
        let kilobytes = try #require(model.rows[.npmCache]?.kilobytes)

        await model.requestClean([.npmCache])
        await waitUntil { model.rows[.npmCache]?.state == .cleaned }
        #expect(model.pendingClean == nil, "the Trash needs no question")
        #expect(!FileManager.default.fileExists(atPath: folder))
        #expect(model.rows[.npmCache]?.canPutBack == true)
        #expect(model.trashedThisSession == kilobytes)
        #expect(model.statusLine.contains("moved to Trash this session"))

        await model.putBack(.npmCache)
        #expect(FileManager.default.fileExists(atPath: folder))
        #expect(model.rows[.npmCache]?.state == .measured)
        #expect(model.trashedThisSession == 0)
    }

    @Test
    func `deleting for good, and what simctl or brew removes, asks first`() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        #expect(model.moveToTrash)
        #expect(!model.needsConfirmation([.npmCache, .derivedData]))
        #expect(model.needsConfirmation([.npmCache, .homebrew]))
        #expect(model.needsConfirmation([.simulators]))
        model.moveToTrash = false
        #expect(model.needsConfirmation([.npmCache]))
    }
}
