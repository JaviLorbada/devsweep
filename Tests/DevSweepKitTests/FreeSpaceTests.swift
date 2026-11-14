import Foundation
import Testing
@testable import DevSweepKit

@Suite("Free space in the report")
struct FreeSpaceTests {
    @Test
    func `the report shows free space as Finder does, before and after a run`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        tools.freeBytes = 123_456_789_012
        home.fill(home.path("\(FakeHome.derivedData)/CompilationCache.noindex"))

        let report = await devclean(home: home, tools: tools)
        #expect(report.output.contains(/(?m)^  Free space now +123\.5 GB$/))

        let run = await devclean("--run", "--yes", home: home, tools: tools)
        #expect(run.output.contains("Done. Free space: 123.5 GB -> 123.5 GB"))
    }

    @Test
    func `without Finder's figure the report falls back to df's`() async {
        let home = FakeHome(), tools = FakeTools(home: home)
        let report = await devclean(home: home, tools: tools)
        #expect(report.output.contains(/(?m)^  Free space now +[0-9.]+ (GB|MB|KB)$/))
    }

    @Test
    func `devclean asks osascript the script's way, with its JavaScript on standard input`() async {
        let runner = RecordingRunner(output: "123456789012\n")
        let bytes = await OsascriptFreeSpace(runner: runner).availableBytes(on: "/Users/someone")
        #expect(bytes == 123_456_789_012)
        #expect(runner.calls == [["osascript", "-l", "JavaScript", "-", "/Users/someone"]])
        #expect(runner.inputs == [Data(OsascriptFreeSpace.script.utf8)])
        #expect(OsascriptFreeSpace.script.contains("'NSURLVolumeAvailableCapacityForImportantUsageKey'"))
    }

    @Test(arguments: [
        ("123", Int64?(123)),
        ("", nil),
        ("12a", nil),
        ("-5", nil),
        (" 5", nil),
        ("1.5", nil),
    ])
    func `only digits are bytes, as the script's case takes them`(text: String, bytes: Int64?) {
        #expect(OsascriptFreeSpace.bytes(text) == bytes)
    }

    @Test
    func `under its own name the tool asks macOS, under the script's it asks osascript`() {
        #expect(Tools.live(environment: [:]).freeSpace is SystemFreeSpace)
        #expect(Tools.live(environment: [:], command: .original).freeSpace is OsascriptFreeSpace)
    }

    @Test
    func `a tool reads its input, and one that ignores it does no harm`() async throws {
        let runner = LiveProcessRunner(environment: [:])
        let echoed = try #require(await runner.run("/bin/cat", [], input: Data("hello\n".utf8)))
        #expect(echoed.text == "hello")
        // More than a pipe holds, to a tool that exits without reading it.
        let ignored = await runner.run("/usr/bin/true", [], input: Data(count: 1_048_576))
        #expect(ignored?.status == 0)
    }
}

/// Answers every run with the same output, and keeps what it was asked.
private final class RecordingRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let output: String
    private var recordedCalls: [[String]] = []
    private var recordedInputs: [Data] = []

    init(output: String) {
        self.output = output
    }

    var calls: [[String]] {
        self.lock.withLock { self.recordedCalls }
    }

    var inputs: [Data] {
        self.lock.withLock { self.recordedInputs }
    }

    func locate(_ name: String) -> String? {
        name
    }

    func run(_ name: String, _ arguments: [String], input: Data?, passthrough: Bool) async -> ProcessOutput? {
        self.lock.withLock {
            self.recordedCalls.append([name] + arguments)
            if let input { self.recordedInputs.append(input) }
        }
        return ProcessOutput(status: 0, standardOutput: Data(self.output.utf8))
    }
}
