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
        #expect(model.currentRuntime == runtimes[1])
        model.selectedRuntime = runtimes[2].id
        #expect(model.currentRuntime == runtimes[2])
        model.selectedRuntime = "gone"
        #expect(model.currentRuntime == runtimes[1])

        var unflagged = sampleExtras
        unflagged.runtimes = [runtimes[0], runtimes[2]]
        let other = makeModel(home: home, extras: unflagged)
        #expect(other.currentRuntime == runtimes[0])
    }

    @Test
    func `a removal simctl refuses says why and keeps the sheet open`() async {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        let runtime = sampleExtras.runtimes[1]
        model.runtimeToRemove = runtime
        // The model's tools have no simctl: the engine refuses before anything runs.
        await model.removeRuntime(runtime)
        #expect(model.runtimeToRemove == runtime)
        #expect(model.runtimeRemovalError?.hasPrefix("simctl couldn't remove it.") == true)
        #expect(!model.isRemovingRuntime)
    }
}
