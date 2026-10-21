import Darwin

/// What `du -sk` would print for one path, and whether every part of it could be read.
public struct Measurement: Sendable, Equatable {
    public var kilobytes: Int64
    /// False when the folder itself could not be read, for example because macOS
    /// denied access to another app's container. The size is then unknown, not zero.
    public var readable: Bool

    public init(kilobytes: Int64, readable: Bool = true) {
        self.kilobytes = kilobytes
        self.readable = readable
    }
}

/// Measures folders the way `du -sk` does: allocated 512-byte blocks of every
/// entry, files with several hard links counted once, symlinks never followed.
///
/// The bash script took its sizes from `du`, and the report has to print the
/// same numbers, so this counts `st_blocks` like `du` rather than asking for
/// `totalFileAllocatedSizeKey`, which counts hard links once per name.
public struct SizeMeasurer: Sendable {
    /// How many entries pass between progress reports.
    public var progressInterval: Int

    public init(progressInterval: Int = 2_000) {
        self.progressInterval = progressInterval
    }

    /// Measures one path. `progress` receives the running total in bytes.
    public func measure(_ path: String, progress: ((Int64) -> Void)? = nil) -> Measurement {
        var blocks: Int64 = 0
        var seenLinks = Set<FileID>()
        var visited = 0
        var readable = true

        FileTree.walk(path) { entry in
            visited += 1
            if visited.isMultiple(of: progressInterval) {
                if Task.isCancelled { return .stop }
                progress?((blocks + 1) / 2 * 1024)
            }
            switch entry.kind {
            case .directory:
                return .proceed
            case .directoryPost:
                blocks += Int64(entry.status?.st_blocks ?? 0)
            case .unreadable, .error:
                if entry.level == 0 { readable = false }
            case .other:
                guard let status = entry.status else { break }
                if status.st_nlink > 1 {
                    let id = FileID(device: status.st_dev, inode: status.st_ino)
                    if !seenLinks.insert(id).inserted { break }
                }
                blocks += Int64(status.st_blocks)
            }
            return .proceed
        }

        let kilobytes = (blocks + 1) / 2
        progress?(kilobytes * 1024)
        return Measurement(kilobytes: kilobytes, readable: readable)
    }

    private struct FileID: Hashable {
        let device: dev_t
        let inode: ino_t
    }
}
