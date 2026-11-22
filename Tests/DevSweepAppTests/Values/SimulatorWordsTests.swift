import DevSweepKit
import Testing
@testable import DevSweepApp

@Suite("Simulator words")
struct SimulatorWordsTests {
    @Test
    func `a flagged simulator's badge says how long it has gone unused`() {
        #expect(SimulatorWords.badge(sampleSimulators[2], staleDays: 90) == "98 days unused")
        #expect(SimulatorWords.badge(sampleSimulators[3], staleDays: 90) == nil)
        #expect(SimulatorWords.badge(sampleSimulators[3], staleDays: 30) == "30 days unused")
        #expect(SimulatorWords.badge(sampleSimulators[0], staleDays: 1) == "1 day unused")
        #expect(SimulatorWords.badge(sampleSimulators[5], staleDays: 0) == nil, "never used")
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
    func `a row says when it was last used, and reads its name, size and badge aloud`() {
        #expect(SimulatorWords.lastUse(sampleSimulators[2]) == "used 2026-07-08")
        #expect(SimulatorWords.lastUse(sampleSimulators[5]) == "never used")
        #expect(SimulatorWords.label(sampleSimulators[2], staleDays: 90) == "iPhone Air, 6.4 GB, 98 days unused")
        #expect(SimulatorWords.label(sampleSimulators[1], staleDays: 90) == "iPhone 16 Pro, 7.2 GB")
    }

    @Test
    func `the inspector says why a flagged one is flagged, and how the others are used`() {
        #expect(SimulatorWords.usageHeading(sampleSimulators[2], staleDays: 90) == "Why it is flagged")
        #expect(SimulatorWords.usageHeading(sampleSimulators[1], staleDays: 90) == "Usage")
        #expect(SimulatorWords.usageHeading(sampleSimulators[1], staleDays: 30) == "Why it is flagged")
    }

    @Test
    func `its status is how it looks, then simctl's state in words`() {
        #expect(SimulatorWords.status(sampleSimulators[2], staleDays: 90) == "looks unused")
        #expect(SimulatorWords.status(sampleSimulators[1], staleDays: 90) == "shut down")
        #expect(SimulatorWords.status(sampleSimulators[0], staleDays: 90) == "booted")
        #expect(SimulatorWords.status(sampleSimulators[5], staleDays: 90) == "shut down")
        let odd = sampleSimulator("Odd", state: "Shutting Down", kilobytes: 1, daysAgo: nil)
        #expect(SimulatorWords.status(odd, staleDays: 90) == "shutting down")
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
