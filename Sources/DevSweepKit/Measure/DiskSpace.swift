import Darwin
import Foundation

/// Space on the volume that holds a path, as `df -k` reports it, and, when
/// asked for, as Finder and System Settings do.
public struct DiskSpace: Sendable, Equatable {
    public var totalKilobytes: Int64
    /// `df -k`'s Available: the blocks free now. The report falls back to
    /// it when Finder's figure can't be read, as the bash script does.
    public var availableKilobytes: Int64
    /// What Finder and System Settings call available: the free blocks and
    /// the space macOS can purge on its own, such as local snapshots and
    /// caches it manages. Nil unless asked for, or when macOS doesn't say.
    public var availableIncludingPurgeableKilobytes: Int64?

    public var usedKilobytes: Int64 {
        max(0, self.totalKilobytes - self.availableKilobytes)
    }

    public init(totalKilobytes: Int64, availableKilobytes: Int64, availableIncludingPurgeableKilobytes: Int64? = nil) {
        self.totalKilobytes = totalKilobytes
        self.availableKilobytes = availableKilobytes
        self.availableIncludingPurgeableKilobytes = availableIncludingPurgeableKilobytes
    }

    /// The "Available" column of `df -k path`, or nil when the path can't be
    /// examined. `includingPurgeable` also asks macOS for the figure Finder
    /// shows, which takes some milliseconds.
    public static func of(_ path: String, includingPurgeable: Bool = false) -> DiskSpace? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        let blockSize = Int64(info.f_bsize)
        return DiskSpace(
            totalKilobytes: Int64(info.f_blocks) * blockSize / 1024,
            availableKilobytes: Int64(info.f_bavail) * blockSize / 1024,
            availableIncludingPurgeableKilobytes: includingPurgeable ? self.availableIncludingPurgeable(path) : nil)
    }

    /// Finder's figure, in kilobytes. A new URL each time: a URL keeps the
    /// values it was asked for, and this one changes.
    private static func availableIncludingPurgeable(_ path: String) -> Int64? {
        let values = try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map { $0 / 1024 }
    }
}
