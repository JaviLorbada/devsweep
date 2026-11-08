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
        let model = await scannedModel(home: home)
        #expect(model.overview.selection == .derivedData)
    }

    @Test
    func `picking a family shows the overview with its biggest item selected`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let model = await scannedModel(home: home)
        model.window.screen = .worktrees
        model.overview.pick(.swiftPackages)
        #expect(model.window.screen == .overview)
        #expect(model.overview.selection == .swiftpmCache)
        model.overview.pick(.npm)
        #expect(model.overview.selection == .npmCache)
    }
}
