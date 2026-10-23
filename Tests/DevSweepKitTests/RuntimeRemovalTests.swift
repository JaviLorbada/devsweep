import Foundation
import Testing
@testable import DevSweepKit

@Suite("Simulator runtimes")
struct RuntimeRemovalTests {
    func runtime(_ id: String) -> SimulatorRuntime {
        SimulatorRuntime(
            id: id,
            identifier: "",
            platform: "iOS",
            version: "1",
            build: "a",
            kilobytes: 1,
            lastUsedDay: nil,
            daysSinceUsed: nil,
            simulatorCount: 0)
    }

    @Test
    func `removing a runtime runs exactly the command the report shows`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.stubRuntimes()
        let engine = try engine(home, tools)
        let old = try #require(await engine.extras().runtimes.first { $0.id == "OLD-RUNTIME" })
        #expect(await engine.removeRuntime(old))
        #expect(tools.log.contains(old.removalCommand))
        #expect(old.removalCommand == "xcrun simctl runtime delete OLD-RUNTIME")
    }

    @Test
    func `A failing simctl is reported`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.simctlDeleteSucceeds = false
        #expect(try await !engine(home, tools).removeRuntime(self.runtime("ABC")))
    }

    @Test(arguments: ["", "-h", "--all"])
    func `ids simctl could read as options are refused before anything runs`(id: String) async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        #expect(try await !engine(home, tools).removeRuntime(self.runtime(id)))
        #expect(!tools.log.calls.contains { $0.contains("runtime delete") })
    }

    @Test
    func `extras can be listed again without a scan, and a scan never removes runtimes`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.stubRuntimes()
        home.makeXcode(home.path("Applications/Xcode.app"), version: "27.0", build: "27A266a")
        let engine = try engine(home, tools)
        _ = await collect(engine)
        let extras = await engine.extras()
        #expect(extras.runtimes.map(\.id) == ["RECENT-RUNTIME", "OLD-RUNTIME"])
        #expect(extras.xcodes.map(\.title) == ["Xcode 27.0 (27A266a)"])
        #expect(!tools.log.calls.contains { $0.contains("runtime delete") })
    }
}
