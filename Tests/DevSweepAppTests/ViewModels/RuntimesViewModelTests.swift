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
        let app = makeApp(home: home, extras: sampleExtras)
        let runtimes = sampleExtras.runtimes
        // iOS 18.5 has no simulators and hasn't been used in 235 days.
        #expect(app.runtimes.current == runtimes[1])
        app.runtimes.select(runtimes[2])
        #expect(app.runtimes.current == runtimes[2])
        // Once the selected runtime is gone, the flagged one again.
        var removed = sampleExtras
        removed.runtimes.removeLast()
        app.scan.showListings(extras: removed, android: nil)
        #expect(app.runtimes.current == runtimes[1])

        var unflagged = sampleExtras
        unflagged.runtimes = [runtimes[0], runtimes[2]]
        let other = makeApp(home: home, extras: unflagged)
        #expect(other.runtimes.current == runtimes[0])
    }

    @Test
    func `a removal simctl refuses says why and keeps the sheet open`() async {
        let home = TemporaryHome()
        let app = makeApp(home: home, extras: sampleExtras)
        let runtime = sampleExtras.runtimes[1]
        app.runtimes.removal.ask(runtime)
        // The app's tools have no simctl: the engine refuses before anything runs.
        await app.runtimes.remove(runtime)
        #expect(app.runtimes.removal.pending == runtime)
        #expect(app.runtimes.removal.error?.hasPrefix("simctl couldn't remove it.") == true)
        #expect(!app.runtimes.removal.isRemoving)
    }
}
