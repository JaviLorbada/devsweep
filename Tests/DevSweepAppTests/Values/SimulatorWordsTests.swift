import DevSweepKit
import Testing
@testable import DevSweepApp

@Suite("Simulator words")
struct SimulatorWordsTests {
    @Test
    func `a stale simulator's badge says how long it has gone unused`() {
        #expect(SimulatorWords.badge(sampleSimulators[2]) == "98 days unused")
        #expect(SimulatorWords.badge(sampleSimulators[3]) == "30 days unused")
        #expect(SimulatorWords.badge(sampleSimulators[0]) == nil)
        #expect(SimulatorWords.badge(sampleSimulators[5]) == nil, "never used")
    }

    @Test
    func `a row names the runtime, and the set when Xcode made it on its own`() {
        #expect(SimulatorWords.detail(sampleSimulators[0]) == "iOS 27.1")
        #expect(SimulatorWords.detail(sampleSimulators[3]) == "iOS 27.1, for previews")
        #expect(SimulatorWords.detail(sampleSimulators[4]) == "iOS 27.1, for tests")
    }

    @Test
    func `the inspector says when it was last used`() {
        #expect(SimulatorWords.usage(sampleSimulators[2]) == "Last used on 2026-07-08, 98 days ago.")
        #expect(SimulatorWords.usage(sampleSimulators[0]) == "Last used on 2026-10-13, 1 day ago.")
        #expect(SimulatorWords.usage(sampleSimulators[5]) == "Never used.")
    }

    @Test
    func `its status is how it looks, then simctl's state in words`() {
        #expect(SimulatorWords.status(sampleSimulators[2]) == "looks unused")
        #expect(SimulatorWords.status(sampleSimulators[0]) == "booted")
        #expect(SimulatorWords.status(sampleSimulators[5]) == "shut down")
        #expect(SimulatorWords.status(sampleSimulator("Odd", state: "Shutting Down", kilobytes: 1, daysAgo: nil))
            == "shutting down")
    }

    @Test
    func `each set says where its simulators come from`() {
        #expect(SimulatorWords.kind(.default) == "Simulator")
        #expect(SimulatorWords.kind(.previews) == "Previews simulator")
        #expect(SimulatorWords.kind(.testing) == "Test clone")
        for set in Simulator.DeviceSet.allCases {
            #expect(!SimulatorWords.origin(set).isEmpty)
        }
        #expect(SimulatorWords.origin(.previews).contains("SwiftUI previews"))
        #expect(SimulatorWords.origin(.testing).contains("in parallel"))
    }
}
