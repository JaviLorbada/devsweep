import Foundation
import Testing
@testable import DevCleanKit

@Suite("Interactive scan")
struct ConcurrentScanTests {
    /// A home with something in every item, several folders per item.
    func richHome() -> (FakeHome, FakeTools) {
        let home = FakeHome(), tools = FakeTools(home: home)
        let dd = home.path(FakeHome.derivedData), p = home.projects
        home.fill("\(dd)/CompilationCache.noindex")
        home.writeZeros("\(dd)/ModuleCache.noindex/blob", kilobytes: 64)
        for n in 1...6 {
            home.mkdir("\(p)/P\(n)/P\(n).xcodeproj")
            home.makeDerivedData(
                "\(dd)/P\(n)-x",
                workspace: "\(p)/P\(n)/P\(n).xcodeproj",
                lastAccessed: "2026-09-0\(n)T10:00:00Z")
            home.writeZeros("\(dd)/P\(n)-x/blob", kilobytes: 8 * n)
            home.touch("\(p)/P\(n)/Package.swift")
            home.writeZeros("\(p)/P\(n)/.build/blob", kilobytes: 4 * n)
        }
        home.fillXcodeBuild("\(p)/P1/build")
        home.touch("\(p)/android/build.gradle")
        home.fill("\(p)/android/build")
        home.fill(home.path("Library/Developer/CoreSimulator/Devices/F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D"))
        tools.unavailableListing = "x (F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D) (Shutdown)\n"
        home.makeDeviceSupport(home.path("\(FakeHome.iosDeviceSupport)/iPhone15,2 27.0 (24A435)"))
        home.makeDeviceSupport(home.path("\(FakeHome.iosDeviceSupport)/iPhone15,2 26.0 (23A100)"))
        home.fill(home.path(FakeHome.deviceInstalls))
        home.fill(home.path("Library/Caches/org.swift.swiftpm"))
        home.fill(home.path(".npm/_cacache"))
        home.fill(home.path(".npm/_npx"))
        home.fill(home.path("Library/Caches/CocoaPods"))
        home.fill(home.path("Library/Caches/Sourcery"))
        tools.brewDryRun = "would free approximately 12MB\n"
        tools.stubRuntimes()
        home.makeXcode(home.path("Applications/Xcode.app"), version: "27.0", build: "27A266a")
        return (home, tools)
    }

    @Test
    func `finds exactly what the report finds`() async throws {
        let (home, tools) = self.richHome()
        let engine = try engine(home, tools)
        let report = await collect(engine)
        var concurrent: [ScanEvent] = []
        for await event in engine.scan(.interactive) {
            concurrent.append(event)
        }

        for item in Item.allCases {
            let a = try #require(report.result(item)), b = try #require(concurrent.result(item))
            #expect(a.paths == b.paths, "\(item)")
            #expect(a.kilobytes == b.kilobytes, "\(item)")
            #expect(a.label == b.label, "\(item)")
            #expect(a.derivedData == b.derivedData, "\(item)")
        }
        let totals = [report, concurrent].map { events in
            events.compactMap {
                if case let .done(total, _) = $0 {
                    total
                } else {
                    nil
                }
            }
        }
        #expect(totals[0] == totals[1])
        #expect(totals[0].count == 1)
        #expect(concurrent.contains {
            if case let .extras(extras) = $0 {
                extras.runtimes.count == 2
            } else {
                false
            }
        })
    }

    @Test
    func `starts the quick items first and DerivedData last`() async throws {
        let (home, tools) = self.richHome()
        var started: [Item] = []
        for await event in try engine(home, tools).scan(.interactive) {
            if case let .started(item) = event { started.append(item) }
        }
        #expect(Set(started) == Set(Item.allCases))
        #expect(Array(started.prefix(4)) == Array(Item.quickestFirst.prefix(4)))
        #expect(started.last == .derivedData)
    }

    @Test
    func `measuring several folders at once gives the same sizes`() async throws {
        let (home, tools) = self.richHome()
        let engine = try engine(home, tools)
        let folders = (1...6).map { "\(engine.policy.homeReal)/Workspace/P\($0)/.build" }
        let base = ScanContext(
            config: engine.config,
            policy: engine.policy,
            dependencies: Dependencies(tools: tools.tools),
            projects: ProjectSearch(roots: [], homeReal: engine.policy.homeReal),
            measurer: SizeMeasurer(progressInterval: 1),
            warn: { _ in })
        let parallel = ScanContext(
            config: engine.config,
            policy: engine.policy,
            dependencies: Dependencies(tools: tools.tools),
            projects: ProjectSearch(roots: [], homeReal: engine.policy.homeReal),
            measurer: SizeMeasurer(progressInterval: 1),
            concurrentFolders: 4,
            warn: { _ in })
        let one = await base.measure(folders) { _ in }
        let four = await parallel.measure(folders) { _ in }
        #expect(one == four)
        #expect(one.map(\.kilobytes) == (1...6).map { Int64(4 * $0) })
    }

    @Test
    func `cancelling stops an interactive scan`() async throws {
        let (home, tools) = self.richHome()
        let engine = try engine(home, tools)
        let task = Task {
            var count = 0
            for await _ in engine.scan(.interactive) {
                count += 1
                if count == 3 { break }
            }
            return count
        }
        #expect(await task.value == 3)
    }
}
