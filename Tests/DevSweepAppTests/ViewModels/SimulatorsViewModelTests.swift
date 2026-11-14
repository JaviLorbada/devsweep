import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Simulators screen")
struct SimulatorsViewModelTests {
    @Test
    func `the simulators Xcode and Simulator show are listed apart from the ones Xcode made for previews and tests`() {
        let model = SimulatorsViewModel(scan: FakeListings(extras: sampleExtras))
        #expect(model.simulators.map(\.name) == [
            "iPhone 18 Pro Max", "iPhone 16 Pro", "iPhone Air", "iPad Pro 13-inch (M5)",
        ])
        #expect(model.previewsAndTests.map(\.name) == ["iPhone 17 Pro", "Clone 1 of iPhone 17 Pro Max"])
        #expect(SimulatorsViewModel(scan: FakeListings()).simulators.isEmpty)
    }

    @Test
    func `the inspector shows the selected simulator, else the first stale one, else the first`() {
        let listings = FakeListings(extras: sampleExtras)
        let model = SimulatorsViewModel(scan: listings)
        // iPhone 16 Pro hasn't been used in 54 days.
        #expect(model.current == sampleSimulators[1])
        model.select(sampleSimulators[4])
        #expect(model.current == sampleSimulators[4])
        // Once the selected one is gone, the stale one again.
        listings.extras = Extras(simulators: Array(sampleSimulators.prefix(4)))
        #expect(model.current == sampleSimulators[1])

        // With none stale, the first; with none at all, none.
        let fresh = FakeListings(extras: Extras(simulators: [sampleSimulators[0], sampleSimulators[5]]))
        #expect(SimulatorsViewModel(scan: fresh).current == sampleSimulators[0])
        #expect(SimulatorsViewModel(scan: FakeListings()).current == nil)
    }

    @Test
    func `the subtitle sums the simulators, or says they are being listed`() {
        let listings = FakeListings()
        listings.isLoadingExtras = true
        let model = SimulatorsViewModel(scan: listings)
        #expect(model.subtitle == "Listing simulators")
        listings.extras = sampleExtras
        #expect(model.subtitle == StatusText.simulators(sampleSimulators, isLoading: true))
    }
}
