import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Simulators screen")
struct SimulatorsViewModelTests {
    let preferences = Preferences(storage: InMemoryPreferencesStore())

    @Test
    func `the simulators Xcode and Simulator show are listed apart from the ones Xcode made for previews and tests`() {
        let model = SimulatorsViewModel(scan: FakeListings(extras: sampleExtras), preferences: self.preferences)
        #expect(model.simulators.map(\.name) == [
            "iPhone 18 Pro Max", "iPhone 16 Pro", "iPhone Air", "iPad Pro 13-inch (M5)",
        ])
        #expect(model.previewsAndTests.map(\.name) == ["iPhone 17 Pro", "Clone 1 of iPhone 17 Pro Max"])
        #expect(SimulatorsViewModel(scan: FakeListings(), preferences: self.preferences).simulators.isEmpty)
    }

    @Test
    func `the inspector shows the selected simulator, else the first flagged one, else the first`() {
        let listings = FakeListings(extras: sampleExtras)
        let model = SimulatorsViewModel(scan: listings, preferences: self.preferences)
        // iPhone Air hasn't been used in 98 days, past the 90 the setting starts at.
        #expect(model.current == sampleSimulators[2])
        model.select(sampleSimulators[4])
        #expect(model.current == sampleSimulators[4])
        // Once the selected one is gone, the flagged one again.
        listings.extras = Extras(simulators: Array(sampleSimulators.prefix(4)))
        #expect(model.current == sampleSimulators[2])

        // With none flagged, the first; with none at all, none.
        let fresh = FakeListings(extras: Extras(simulators: [sampleSimulators[0], sampleSimulators[5]]))
        #expect(SimulatorsViewModel(scan: fresh, preferences: self.preferences).current == sampleSimulators[0])
        #expect(SimulatorsViewModel(scan: FakeListings(), preferences: self.preferences).current == nil)
    }

    @Test
    func `how long unused flags a simulator is the setting runtimes use`() {
        let model = SimulatorsViewModel(scan: FakeListings(extras: sampleExtras), preferences: self.preferences)
        self.preferences.staleDays = 30
        #expect(model.staleDays == 30)
        // iPhone 16 Pro, 54 days unused, is now the first flagged.
        #expect(model.current == sampleSimulators[1])
    }

    @Test
    func `the subtitle sums the simulators, or says they are being listed`() {
        let listings = FakeListings()
        listings.isLoadingExtras = true
        let model = SimulatorsViewModel(scan: listings, preferences: self.preferences)
        #expect(model.subtitle == "Listing simulators")
        listings.extras = sampleExtras
        #expect(model.subtitle == StatusText.simulators(sampleSimulators, staleDays: 90, isLoading: true))
    }

    @Test
    func `each card says when it flags, and why it has none`() {
        let listings = FakeListings()
        listings.isLoadingExtras = true
        let model = SimulatorsViewModel(scan: listings, preferences: self.preferences)
        #expect(model.noSimulators == "Listing simulators…")
        #expect(model.noPreviewsOrTests == "Listing simulators…")
        listings.isLoadingExtras = false
        #expect(model.noSimulators == "No simulators found.")
        #expect(model.noPreviewsOrTests == "Xcode made none for previews or tests.")
        #expect(model.note == "flagged after 90 days unused")
        self.preferences.staleDays = 30
        #expect(model.note == "flagged after 30 days unused")
    }
}
