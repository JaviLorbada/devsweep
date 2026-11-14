import DevSweepKit
import Testing
@testable import DevSweepApp

@Suite("Item copy")
struct ItemCopyTests {
    @Test
    func `other languages' build folders never start ticked, and every other item can`() {
        let neverTicked: Set<Item> = [.cocoapodsPods, .cargoBuilds, .nodeModules]
        for item in Item.allCases {
            #expect(item.canStartTicked == !neverTicked.contains(item), "\(item)")
        }
    }

    @Test
    func `build folders' short names say they are folders`() {
        #expect(Item.nodeModules.shortName == "node_modules folders")
        #expect(Item.cocoapodsPods.shortName == "Pods folders")
        #expect(Item.cargoBuilds.shortName == "Cargo target folders")
    }
}
