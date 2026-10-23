import Foundation
import Testing
@testable import DevSweepKit

func engine(
    _ home: FakeHome,
    _ tools: FakeTools,
    skipped: Set<Item> = [],
    includeExtras: Bool = true) throws -> Engine
{
    var config = ScanConfig.fromEnvironment(home.environment, skipped: skipped, includeExtras: includeExtras)
    config.environment = home.environment
    return try Engine(config: config, tools: tools.tools, measurer: SizeMeasurer(progressInterval: 2))
}

func collect(_ engine: Engine) async -> [ScanEvent] {
    var events: [ScanEvent] = []
    for await event in engine.scan() {
        events.append(event)
    }
    return events
}

extension [ScanEvent] {
    var results: [ItemResult] {
        compactMap {
            if case let .finished(result) = $0 {
                result
            } else {
                nil
            }
        }
    }

    func result(_ item: Item) -> ItemResult? { self.results.first { $0.item == item } }
}

@Suite("Scanning")
struct ScanTests {
    @Test
    func `events arrive in order: folders, each item, done, extras`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path("Library/Caches/org.swift.swiftpm"))
        let events = try await collect(engine(home, tools, skipped: [.homebrew]))

        guard case let .projectFolders(folders) = events.first else { Issue.record("no project folders first"); return }
        #expect(folders.found == ["~/Workspace"])
        let kinds = events.map { event -> String in
            switch event {
            case .projectFolders: "folders"
            case let .started(item): "start \(item.rawValue)"
            case .progress: "progress"
            case .warning: "warning"
            case let .finished(result): "finish \(result.item.rawValue)"
            case .done: "done"
            case .extras: "extras"
            case .android: "android"
            }
        }.filter { $0 != "progress" }
        let expected = ["folders"] + Item.allCases.filter { $0 != .homebrew }.flatMap { [
            "start \($0.rawValue)",
            "finish \($0.rawValue)",
        ] }
            + ["done", "extras"]
        #expect(kinds == expected)
        #expect(events.contains {
            if case let .progress(.swiftpmCache, bytes) = $0 {
                bytes == 4096
            } else {
                false
            }
        })
        guard case let .done(total, _) = events[events.count - 2] else { Issue.record("no done"); return }
        #expect(total == 4096)
    }

    @Test
    func `without extras the scan ends at done`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let events = try await collect(engine(home, tools, includeExtras: false))
        guard case .done = events.last else { Issue.record("last event is not done"); return }
        #expect(!tools.log.contains("xcrun simctl runtime list -j"))
        #expect(!tools.log.contains("xcode-select -p"))
    }

    @Test
    func `results hold resolved, sorted paths and the breakdown`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path("Library/Caches/JetBrains/Toolbox/download"))
        home.fill(home.path("Library/Caches/CocoaPods"))
        home.fill(home.path("\(FakeHome.derivedData)/ModuleCache.noindex"))
        let engine = try engine(home, tools)
        let events = await collect(engine)

        let caches = try #require(events.result(.toolCaches))
        #expect(caches.paths == [
            "\(engine.policy.homeReal)/Library/Caches/CocoaPods",
            "\(engine.policy.homeReal)/Library/Caches/JetBrains/Toolbox/download",
        ])
        #expect(caches.kilobytes == 8)
        #expect(caches.label == "Tool caches (2)")
        let derived = try #require(events.result(.derivedData))
        #expect(derived.derivedData?.moduleCacheKilobytes == 4)
        #expect(derived.kilobytes == 4)
        #expect(events.result(.homebrew)?.location == "brew cleanup --prune=all")
    }

    @Test
    func `homebrew that isn't installed says so and costs nothing`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.brewInstalled = false
        let events = try await collect(engine(home, tools))
        #expect(events.result(.homebrew)?.location == "Homebrew not installed")
        #expect(!tools.log.calls.contains { $0.hasPrefix("brew") })
    }

    @Test
    func `simulators aren't asked for when xcrun is missing`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.simctlInstalled = false
        tools.unavailableListing = "x (F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D)"
        home.fill(home.path("Library/Developer/CoreSimulator/Devices/F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D"))
        let events = try await collect(engine(home, tools))
        #expect(events.result(.simulators)?.paths == [])
        #expect(!tools.log.calls.contains { $0.hasPrefix("xcrun") })
    }

    @Test
    func `A folder that can't be read is listed with an unknown size`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        home.fill(home.path(FakeHome.deviceInstalls))
        chmod(home.path(FakeHome.deviceInstalls), 0o100)
        defer { chmod(home.path(FakeHome.deviceInstalls), 0o755) }
        let events = try await collect(engine(home, tools))
        let result = try #require(events.result(.deviceInstalls))
        #expect(result.paths.count == 1)
        #expect(!result.sizeKnown)
        #expect(result.isEmpty)
    }

    @Test
    func `the build folder search prunes .git, node_modules, Pods, DerivedData and ~/Library`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        for folder in ["node_modules/x", "Pods/x", "DerivedData/x", "nested/.git/x", "ok"] {
            home.touch("\(home.projects)/\(folder)/Package.swift")
            home.fill("\(home.projects)/\(folder)/.build")
        }
        home.touch(home.path("Library/App/Package.swift"))
        home.fill(home.path("Library/App/.build"))
        home.touch(home.path("Other/Package.swift"))
        home.fill(home.path("Other/.build"))
        var config = ScanConfig.fromEnvironment(home.environment, projects: "\(home.projects):~")
        config.environment = home.environment
        let engine = try Engine(config: config, tools: tools.tools)
        let paths = await collect(engine).result(.swiftpmBuilds)?.paths ?? []
        #expect(paths == ["\(engine.policy.homeReal)/Other/.build", "\(engine.policy.homeReal)/Workspace/ok/.build"])
    }

    @Test
    func `running apps block cleaning only when an Xcode item would be cleaned`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.running = [.simulator]
        #expect(try await engine(home, tools).runningAppsBlockingClean() == [.simulator])
        #expect(try await engine(home, tools, skipped: [.derivedData, .simulators, .deviceInstalls, .deviceSupport])
            .runningAppsBlockingClean() == [])
    }

    @Test
    func `cancelling the consumer stops the scan`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        for n in 0..<200 {
            home.fill(home.path("\(FakeHome.derivedData)/P\(n)"))
        }
        let engine = try engine(home, tools)
        let task = Task {
            var count = 0
            for await event in engine.scan() {
                count += 1
                if case .started(.derivedData) = event { break }
            }
            return count
        }
        let count = await task.value
        #expect(count == 2)
    }
}
