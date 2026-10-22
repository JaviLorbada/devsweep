import Darwin

/// Space on the volume that holds a path, as `df -k` reports it.
public struct DiskSpace: Sendable, Equatable {
    public var totalKilobytes: Int64
    public var availableKilobytes: Int64

    public var usedKilobytes: Int64 {
        max(0, self.totalKilobytes - self.availableKilobytes)
    }

    public init(totalKilobytes: Int64, availableKilobytes: Int64) {
        self.totalKilobytes = totalKilobytes
        self.availableKilobytes = availableKilobytes
    }

    /// The "Available" column of `df -k path`, or nil when the path can't be examined.
    public static func of(_ path: String) -> DiskSpace? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        let blockSize = Int64(info.f_bsize)
        return DiskSpace(
            totalKilobytes: Int64(info.f_blocks) * blockSize / 1024,
            availableKilobytes: Int64(info.f_bavail) * blockSize / 1024)
    }
}
