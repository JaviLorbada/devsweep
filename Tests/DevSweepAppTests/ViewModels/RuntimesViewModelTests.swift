import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Simulator runtimes screen")
struct RuntimesViewModelTests {
    let preferences = Preferences(storage: InMemoryPreferencesStore())

    @Test
    func `the inspector shows the selected runtime, else the first flagged, else the first`() {
        let listings = FakeListings(extras: sampleExtras)
        let model = RuntimesViewModel(scan: listings, preferences: self.preferences)
        let runtimes = sampleExtras.runtimes
        // iOS 18.5 has no simulators and hasn't been used in 235 days.
        #expect(model.current == runtimes[1])
        model.select(runtimes[2])
        #expect(model.current == runtimes[2])
        // Once the selected runtime is gone, the flagged one again.
        listings.extras?.runtimes.removeLast()
        #expect(model.current == runtimes[1])

        // With nothing selected and nothing flagged, the first.
        let unflagged = FakeListings(extras: sampleExtras)
        unflagged.extras?.runtimes = [runtimes[0], runtimes[2]]
        #expect(RuntimesViewModel(scan: unflagged, preferences: self.preferences).current == runtimes[0])
    }

    @Test
    func `how long unused flags a runtime is a preference`() {
        let model = RuntimesViewModel(scan: FakeListings(extras: sampleExtras), preferences: self.preferences)
        self.preferences.staleDays = 30
        #expect(model.staleDays == 30)
    }

    @Test
    func `a removal simctl refuses says why and keeps the sheet open`() async {
        let listings = FakeListings(extras: sampleExtras)
        listings.removes = false
        let model = RuntimesViewModel(scan: listings, preferences: self.preferences)
        let runtime = sampleExtras.runtimes[1]
        model.askToRemove(runtime)
        await model.remove(runtime)
        #expect(listings.askedToRemove == [runtime.id])
        #expect(model.removal.pending == runtime)
        #expect(model.removal.error?.hasPrefix("simctl couldn't remove it.") == true)
        #expect(!model.removal.isRemoving)
    }

    @Test
    func `a removal that works closes the sheet and lets go of the selection`() async {
        let listings = FakeListings(extras: sampleExtras)
        let model = RuntimesViewModel(scan: listings, preferences: self.preferences)
        let runtime = sampleExtras.runtimes[2]
        model.askToRemove(runtime)
        #expect(model.current == runtime)
        await model.remove(runtime)
        #expect(model.removal.pending == nil)
        #expect(model.current == sampleExtras.runtimes[1], "the flagged one again")
    }
}
