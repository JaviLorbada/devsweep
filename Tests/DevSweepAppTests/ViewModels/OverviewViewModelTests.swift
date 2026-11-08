import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Overview")
struct OverviewViewModelTests {
    @Test
    func `a finished scan selects the biggest item when nothing is selected`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let app = await scannedApp(home: home)
        #expect(app.overview.selection == .derivedData)
    }

    @Test
    func `picking a family shows the overview with its biggest item selected`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let app = await scannedApp(home: home)
        app.window.screen = .worktrees
        app.overview.pick(.swiftPackages)
        #expect(app.window.screen == .overview)
        #expect(app.overview.selection == .swiftpmCache)
        app.overview.pick(.npm)
        #expect(app.overview.selection == .npmCache)
    }
}
