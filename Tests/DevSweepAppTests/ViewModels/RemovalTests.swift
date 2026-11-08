import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Removal sheets")
struct RemovalTests {
    @Test
    func `a removal that works closes the sheet, and one that fails keeps it open and says why`() async {
        let removal = Removal<SimulatorRuntime>()
        let runtime = sampleExtras.runtimes[1]
        removal.ask(runtime)
        #expect(removal.pending == runtime)

        var removed = await removal.run(runtime, failure: "It stayed.") { _ in false }
        #expect(!removed)
        #expect(removal.pending == runtime)
        #expect(removal.error == "It stayed.")
        #expect(!removal.isRemoving)

        removal.clearError()
        #expect(removal.error == nil)
        removed = await removal.run(runtime, failure: "It stayed.") { _ in true }
        #expect(removed)
        #expect(removal.pending == nil)
        #expect(removal.error == nil)
    }
}
