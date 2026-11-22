import Foundation
import Testing
@testable import DevSweepKit

@Suite("Simulator listing")
struct SimulatorListingTests {
    let now = Date(timeIntervalSince1970: JavaScriptDate.parse("2026-11-14T12:00:00Z")! / 1000)

    /// The three device sets of a Mac with a booted iPhone, an iPad never
    /// used, an iPhone unused since August, one whose runtime is gone, a
    /// preview device and a test clone.
    var lists: [Simulator.DeviceSet: SimctlDeviceList] {
        [
            .default: SimctlDeviceList(Data(fixture("simctl-devices.json").utf8)),
            .previews: SimctlDeviceList(Data(fixture("simctl-devices-previews.json").utf8)),
            .testing: SimctlDeviceList(Data(fixture("simctl-devices-testing.json").utf8)),
        ]
    }

    @Test
    func `each simulator has its name, runtime, state, size and last use, the largest first`() {
        let simulators = ExtrasScanner.simulators(self.lists, now: self.now)
        #expect(simulators.map(\.name) == [
            "iPhone 18 Pro Max", "iPhone Air", "iPhone 17 Pro", "Clone 1 of iPhone 17", "iPad Air 13-inch (M4)",
            "iPhone 17",
        ])
        #expect(simulators.map(\.deviceSet) == [.default, .default, .previews, .testing, .default, .default])
        #expect(simulators[0] == Simulator(
            id: "79CDB9F9-4BD5-4272-A90E-ADDD1FB2A156",
            name: "iPhone 18 Pro Max",
            runtime: "iOS 27.0",
            state: "Booted",
            kilobytes: 10_081_016,
            lastUsedDay: "2026-11-13",
            daysSinceUsed: 0,
            deviceSet: .default,
            isAvailable: true))
        #expect(simulators[1].runtime == "iOS 26.5")
        #expect(simulators[1].daysSinceUsed == 98)
        #expect(simulators[4].kilobytes == 18020)
        #expect(simulators[4].lastUsedDay == nil)
        #expect(simulators[4].daysSinceUsed == nil)
    }

    @Test
    func `a simulator is flagged once unused for the days given, and one never used is not`() {
        let simulators = ExtrasScanner.simulators(self.lists, now: self.now)
        let flagged = { (days: Int) in simulators.filter { $0.flagReason(staleDays: days) != nil }.map(\.name) }
        // The preview device was last used exactly 30 days ago, the iPhone Air 98.
        #expect(flagged(30) == ["iPhone Air", "iPhone 17 Pro", "iPhone 17"])
        #expect(flagged(90) == ["iPhone Air", "iPhone 17"])
        #expect(simulators[1].flagReason(staleDays: 90) == "Not used in 98 days")
        #expect(simulators.first { $0.daysSinceUsed == nil }?.flagReason(staleDays: 0) == nil)
    }

    @Test
    func `a simulator whose runtime is gone says so, and one simctl says nothing about is available`() {
        let simulators = ExtrasScanner.simulators(self.lists, now: self.now)
        #expect(simulators.filter { !$0.isAvailable }.map(\.id) == ["0CD98AA9-475F-4336-BCD7-383B43BC4DBA"])
        let unsure = SimctlDeviceList(Data(#"""
        { "devices": { "R": [ { "udid": "A" }, { "udid": "B", "isAvailable": "no" } ] } }
        """#.utf8))
        let listed = ExtrasScanner.simulators([.default: unsure], now: self.now)
        #expect(listed.map(\.isAvailable) == [true, true])
    }

    @Test
    func `the runtimes count every entry under them, simulators or not`() {
        let list = SimctlDeviceList(Data(#"""
        { "devices": { "R": [ { "udid": "A", "name": 5, "dataPathSize": "big" }, { "name": "no UDID" }, 7, null ],
                       "S": "x" } }
        """#.utf8))
        #expect(list.count(for: "R") == 4)
        #expect(list.count(for: "S") == 0)
    }

    @Test
    func `an entry that isn't a simulator or has no UDID is left out, and a field of another type counts as missing`() {
        let list = SimctlDeviceList(Data(#"""
        { "devices": { "R": [ { "udid": "A", "name": 5, "dataPathSize": "big" }, { "name": "no UDID" }, 7, null ] } }
        """#.utf8))
        let simulators = ExtrasScanner.simulators([.default: list], now: self.now)
        #expect(simulators.map(\.id) == ["A"])
        #expect(simulators[0].name == "?")
        #expect(simulators[0].state == "?")
        #expect(simulators[0].kilobytes == 0)
        #expect(ExtrasScanner.simulators([.default: SimctlDeviceList(Data("nope".utf8))], now: self.now).isEmpty)
    }

    @Test(arguments: [
        ("com.apple.CoreSimulator.SimRuntime.iOS-27-2", "iOS 27.2"),
        ("com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4", "iOS 27.2"),
        ("com.apple.CoreSimulator.SimRuntime.watchOS-26-1", "watchOS 26.1"),
        ("com.apple.CoreSimulator.SimRuntime.xrOS-2-0", "xrOS 2.0"),
        ("plain", "plain"),
    ])
    func `a simulator's runtime is named from its identifier`(identifier: String, name: String) {
        #expect(ExtrasScanner.runtimeName(of: identifier) == name)
    }

    @Test
    func `simulators of one size go by name, then by UDID`() {
        let list = SimctlDeviceList(Data(#"""
        { "devices": { "R": [
          { "udid": "B", "name": "iPhone", "dataPathSize": 1024 },
          { "udid": "C", "name": "iPad", "dataPathSize": 1024 },
          { "udid": "A", "name": "iPhone", "dataPathSize": 1024 },
          { "udid": "D", "name": "Apple TV", "dataPathSize": 2048 } ] } }
        """#.utf8))
        #expect(ExtrasScanner.simulators([.default: list], now: self.now).map(\.id) == ["D", "C", "A", "B"])
    }

    @Test
    func `only the app's scan lists simulators, from all three sets, reading the default set once`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.stubRuntimes()
        tools.stubDeviceSets()
        let commandLine = try engine(home, tools)
        #expect(!commandLine.config.includeSimulators)
        #expect(await commandLine.extras().simulators.isEmpty)
        #expect(!tools.log.calls.contains { $0.contains("--set") })

        var config = commandLine.config
        config.includeSimulators = true
        let calls = tools.log.calls.count
        let extras = try await Engine(config: config, tools: tools.tools).extras()
        #expect(extras.simulators.count == 6)
        #expect(Set(extras.simulators.map(\.deviceSet)) == [.default, .previews, .testing])
        #expect(extras.runtimes.first { $0.id == "RECENT-RUNTIME" }?.simulatorCount == 2)
        let listings = tools.log.calls.dropFirst(calls).filter { $0.hasSuffix("list devices -j") }
        #expect(listings == [
            "xcrun simctl list devices -j",
            "xcrun simctl --set previews list devices -j",
            "xcrun simctl --set testing list devices -j",
        ])
    }

    @Test
    func `without simctl the app's scan lists no simulators and asks simctl nothing`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.simctlInstalled = false
        tools.stubRuntimes()
        tools.stubDeviceSets()
        var config = try engine(home, tools).config
        config.includeSimulators = true
        let extras = try await Engine(config: config, tools: tools.tools).extras()
        #expect(extras.simulators.isEmpty)
        #expect(!tools.log.calls.contains { $0.hasPrefix("xcrun simctl") })
    }

    @Test
    func `each device set is listed by the name simctl gives it`() async {
        let runner = RecordingRunner(output: "{}")
        let simctl = LiveSimctlClient(runner: runner)
        for set in Simulator.DeviceSet.allCases {
            _ = await simctl.devicesJSON(in: set)
        }
        #expect(runner.calls == [
            ["xcrun", "simctl", "list", "devices", "-j"],
            ["xcrun", "simctl", "--set", "previews", "list", "devices", "-j"],
            ["xcrun", "simctl", "--set", "testing", "list", "devices", "-j"],
        ])
    }
}
