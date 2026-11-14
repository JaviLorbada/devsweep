import Foundation

/// The free space Finder and System Settings show for a volume: what is free
/// now and what macOS frees on its own when space runs low, such as local
/// snapshots and caches it manages.
public protocol FreeSpaceReading: Sendable {
    /// Bytes available on the volume that holds `path`, nil when macOS
    /// doesn't say.
    func availableBytes(on path: String) async -> Int64?
}

/// Asks macOS directly, as the app and `devsweep` do.
public struct SystemFreeSpace: FreeSpaceReading {
    public init() {}

    public func availableBytes(on path: String) async -> Int64? {
        // A new URL each time: a URL keeps the values it was asked for.
        let values = try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

/// Asks the way the bash script does, through `osascript` on `PATH`, so that
/// run under the script's name the tool answers its bats suite, which stubs
/// `osascript`. The same JavaScript, given on standard input.
public struct OsascriptFreeSpace: FreeSpaceReading {
    let runner: any ProcessRunning

    public init(runner: any ProcessRunning) {
        self.runner = runner
    }

    static let script = """
    ObjC.import('Foundation');
    function run(argv) {
      const key = 'NSURLVolumeAvailableCapacityForImportantUsageKey';
      const values = $.NSURL.fileURLWithPath(argv[0]).resourceValuesForKeysError($([key]), null);
      const bytes = values.isNil() ? undefined : ObjC.unwrap(values.objectForKey(key));
      return typeof bytes === 'number' ? String(bytes) : '';
    }

    """

    /// What `osascript` prints, whatever its exit status, when it is digits
    /// and nothing else, as the script's `case` takes it.
    public func availableBytes(on path: String) async -> Int64? {
        guard let output = await runner.run("osascript", ["-l", "JavaScript", "-", path], input: Data(Self.script.utf8))
        else { return nil }
        return Self.bytes(output.text)
    }

    static func bytes(_ text: String) -> Int64? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) })
        else { return nil }
        return Int64(text)
    }
}
