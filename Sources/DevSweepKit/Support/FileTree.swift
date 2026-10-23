import Darwin

/// A physical walk over a folder with fts(3), the way `find` and `du` walk:
/// symlinks are never followed, not even the root, and the process working
/// directory is never changed, so walks can run on several threads at once.
enum FileTree {
    enum Kind {
        /// A directory, before its children.
        case directory
        /// A directory, after its children.
        case directoryPost
        /// A directory that could not be read.
        case unreadable
        /// Anything else fts could stat: files, symlinks, sockets.
        case other
        /// An entry fts could not stat, or a directory cycle.
        case error
    }

    struct Entry {
        let path: String
        let name: String
        let level: Int
        let kind: Kind
        let status: stat?
    }

    enum Decision {
        case proceed
        /// Do not descend into this directory.
        case skipChildren
        /// End the walk.
        case stop
    }

    static func walk(_ root: String, _ visit: (Entry) -> Decision) {
        guard let rootCopy = strdup(root) else { return }
        defer { free(rootCopy) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [rootCopy, nil]
        guard let stream = fts_open(&arguments, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return }
        defer { fts_close(stream) }

        while let node = fts_read(stream) {
            let info = Int32(node.pointee.fts_info)
            let kind: Kind = switch info {
            case FTS_D: .directory
            case FTS_DP: .directoryPost
            case FTS_DNR: .unreadable
            case FTS_ERR, FTS_NS, FTS_DC: .error
            default: .other
            }
            let path = String(cString: node.pointee.fts_path)
            let level = Int(node.pointee.fts_level)
            // fts names the root by the whole argument; find matches its basename.
            let name = level == 0 ? FileSystem.basename(path) : self.entryName(node)
            let status: stat? = (kind == .error || node.pointee.fts_statp == nil) ? nil : node.pointee.fts_statp.pointee
            switch visit(Entry(path: path, name: name, level: level, kind: kind, status: status)) {
            case .proceed:
                break
            case .skipChildren:
                if kind == .directory {
                    fts_set(stream, node, FTS_SKIP)
                }
            case .stop:
                return
            }
        }
    }

    private static func entryName(_ node: UnsafeMutablePointer<FTSENT>) -> String {
        withUnsafePointer(to: &node.pointee.fts_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(node.pointee.fts_namelen) + 1) {
                String(cString: $0)
            }
        }
    }
}
