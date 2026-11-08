import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Simulator runtimes screen")
struct RuntimesViewModelTests {
    @Test
    func `the inspector shows the selected runtime, else the first flagged, else the first`() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        let runtimes = sampleExtras.runtimes
        // iOS 18.5 has no simulators and hasn't been used in 235 days.
        #expect(model.runtimes.current == runtimes[1])
        model.runtimes.select(runtimes[2])
        #expect(model.runtimes.current == runtimes[2])
        // Once the selected runtime is gone, the flagged one again.
        var removed = sampleExtras
        removed.runtimes.removeLast()
        model.scan.showListings(extras: removed, android: nil)
        #expect(model.runtimes.current == runtimes[1])

        var unflagged = sampleExtras
        unflagged.runtimes = [runtimes[0], runtimes[2]]
        let other = makeModel(home: home, extras: unflagged)
        #expect(other.runtimes.current == runtimes[0])
    }

    @Test
    func `a removal simctl refuses says why and keeps the sheet open`() async {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        let runtime = sampleExtras.runtimes[1]
        model.runtimes.removal.ask(runtime)
        // The model's tools have no simctl: the engine refuses before anything runs.
        await model.runtimes.remove(runtime)
        #expect(model.runtimes.removal.pending == runtime)
        #expect(model.runtimes.removal.error?.hasPrefix("simctl couldn't remove it.") == true)
        #expect(!model.runtimes.removal.isRemoving)
    }
}
