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
        #expect(model.selection == .derivedData)
    }

    @Test
    func `picking a family shows the overview with its biggest item selected`() async {
        let home = TemporaryHome()
        writeFourItems(in: home)
        let model = await scannedModel(home: home)
        model.screen = .worktrees
        model.pick(.swiftPackages)
        #expect(model.screen == .overview)
        #expect(model.selection == .swiftpmCache)
        model.pick(.npm)
        #expect(model.selection == .npmCache)
    }
}
