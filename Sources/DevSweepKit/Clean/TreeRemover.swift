import Darwin
import Dispatch
import Synchronization

/// Deletes a folder and everything in it, like `rm -rf`, two to three times
/// faster than `FileManager`: four threads share the work, and each
/// directory's files go in the order of their inode numbers, which APFS
/// removes about twice as fast as the order the directory lists them in.
/// Four threads beat eight: past that, APFS makes them wait on each other.
///
/// Every step starts from the folder's parent, opened once, and refuses a
/// symlink anywhere along the way, so nothing the walk meets can lead it out
/// of the folder. A symlink inside is removed itself, as `rm` does.
/// Directories are listed with `getattrlistbulk`, which also gives each
/// file's allocated size for the progress at no extra cost; a `stat` per file
/// made the whole thing 40% slower.
enum TreeRemover {
    static let threads = 4

    /// Whether everything went. `progress` receives the bytes removed so
    /// far, from any of the threads.
    static func remove(_ path: String, progress: (@Sendable (Int64) -> Void)? = nil) -> Bool {
        let base = open(FileSystem.dirname(path), O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard base >= 0 else { return false }
        defer { close(base) }
        let removal = Removal(base: base, progress: progress)
        removal.push([.list(Removal.Directory(path: FileSystem.basename(path), parent: nil))])
        DispatchQueue.concurrentPerform(iterations: self.threads) { _ in removal.work() }
        return !removal.failed.load(ordering: .relaxed)
    }
}

private final class Removal: Sendable {
    /// A directory being emptied, by its path from the base.
    final class Directory: Sendable {
        let path: String
        let parent: Directory?
        /// Its listings and subdirectories still to finish; at zero it goes.
        let pending = Atomic<Int>(0)

        init(path: String, parent: Directory?) {
            self.path = path
            self.parent = parent
        }
    }

    struct File: Sendable {
        let name: String
        let bytes: Int64
    }

    enum Work: Sendable {
        /// List a directory, delete its files and queue its subdirectories.
        case list(Directory)
        /// Delete some of a big directory's files.
        case unlink(Directory, ArraySlice<File>)
    }

    struct Queue {
        var stack: [Work] = []
        /// Work queued or running; at zero the removal is over.
        var outstanding = 0
    }

    /// Big directories' files are split into chunks this size, so the
    /// threads can share one directory.
    static let chunk = 512
    static let openFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC

    let base: Int32
    let progress: (@Sendable (Int64) -> Void)?
    let queue = Mutex(Queue())
    /// Signaled once per queued work, and once per thread when it is all done.
    let ready = DispatchSemaphore(value: 0)
    let failed = Atomic(false)
    let removedBytes = Atomic<Int64>(0)

    init(base: Int32, progress: (@Sendable (Int64) -> Void)?) {
        self.base = base
        self.progress = progress
    }

    func push(_ work: [Work]) {
        self.queue.withLock {
            $0.stack.append(contentsOf: work)
            $0.outstanding += work.count
        }
        for _ in work {
            self.ready.signal()
        }
    }

    /// One thread's loop. The stack is last in, first out, so the walk goes
    /// deep before wide and holds few paths at once.
    func work() {
        while true {
            self.ready.wait()
            guard let next = queue.withLock({ $0.stack.popLast() }) else { return }
            self.run(next)
            let over = self.queue.withLock {
                $0.outstanding -= 1
                return $0.outstanding == 0
            }
            if over {
                for _ in 0..<TreeRemover.threads {
                    self.ready.signal()
                }
            }
        }
    }

    private func run(_ work: Work) {
        switch work {
        case let .list(directory):
            self.list(directory)
        case let .unlink(directory, files):
            let fd = openat(base, directory.path, Self.openFlags)
            if fd >= 0 {
                self.unlink(files, in: fd)
                close(fd)
            } else {
                self.fail()
            }
            self.childFinished(directory)
        }
    }

    private func list(_ directory: Directory) {
        let fd = openat(base, directory.path, Self.openFlags)
        guard fd >= 0 else {
            switch errno {
            case ENOENT: break
            // A file or a symlink now, not a directory: it goes itself. A
            // symlink further up makes this fail too, and is left alone.
            case ENOTDIR, ELOOP:
                if unlinkat(self.base, directory.path, AT_SYMLINK_NOFOLLOW_ANY) != 0, errno != ENOENT {
                    self.fail()
                }
            default: self.fail()
            }
            directory.parent.map(self.childFinished)
            return
        }
        let (files, subdirectories) = self.entries(fd)
        var work: [Work] = []
        if files.count <= Self.chunk {
            self.unlink(files[...], in: fd)
        } else {
            for start in stride(from: 0, to: files.count, by: Self.chunk) {
                work.append(.unlink(directory, files[start..<min(start + Self.chunk, files.count)]))
            }
        }
        close(fd)
        for name in subdirectories {
            work.append(.list(Directory(path: "\(directory.path)/\(name)", parent: directory)))
        }
        if work.isEmpty {
            self.finish(directory)
        } else {
            directory.pending.store(work.count, ordering: .releasing)
            self.push(work)
        }
    }

    /// A directory's files in inode order, and its subdirectories.
    private func entries(_ fd: Int32) -> (files: [File], subdirectories: [String]) {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_FILEID)
        list.fileattr = attrgroup_t(ATTR_FILE_ALLOCSIZE)
        let size = 128 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { buffer.deallocate() }

        var files: [(file: File, inode: UInt64)] = []
        var subdirectories: [String] = []
        while true {
            let count = getattrlistbulk(fd, &list, buffer, size, 0)
            if count < 0 { self.fail() }
            guard count > 0 else { break }
            // Each entry: its length, the attributes returned, then each
            // attribute in order. The name's offset counts from its own field.
            var entry = buffer
            for _ in 0..<count {
                var field = entry + MemoryLayout<UInt32>.size
                let returned = field.loadUnaligned(as: attribute_set_t.self)
                field += MemoryLayout<attribute_set_t>.size
                let nameOffset = Int(field.loadUnaligned(as: Int32.self))
                let name = String(cString: (field + nameOffset).assumingMemoryBound(to: CChar.self))
                field += MemoryLayout<attrreference_t>.size
                let type = field.loadUnaligned(as: fsobj_type_t.self)
                field += MemoryLayout<fsobj_type_t>.size
                let inode = field.loadUnaligned(as: UInt64.self)
                field += MemoryLayout<UInt64>.size
                if type == VDIR.rawValue {
                    subdirectories.append(name)
                } else {
                    let bytes = returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0
                        ? field.loadUnaligned(as: off_t.self) : 0
                    files.append((File(name: name, bytes: bytes), inode))
                }
                entry += Int(entry.loadUnaligned(as: UInt32.self))
            }
        }
        files.sort { $0.inode < $1.inode }
        return (files.map(\.file), subdirectories)
    }

    private func unlink(_ files: ArraySlice<File>, in fd: Int32) {
        var removed: Int64 = 0
        for file in files {
            // A name from the listing is one component; the flag makes sure.
            if Darwin.unlinkat(fd, file.name, AT_SYMLINK_NOFOLLOW_ANY) == 0 {
                removed += file.bytes
            } else if errno != ENOENT {
                self.fail()
            }
        }
        let total = self.removedBytes.wrappingAdd(removed, ordering: .relaxed).newValue
        self.progress?(total)
    }

    private func childFinished(_ directory: Directory) {
        if directory.pending.wrappingSubtract(1, ordering: .acquiringAndReleasing).newValue == 0 {
            self.finish(directory)
        }
    }

    /// Everything in it is done: the directory goes, and its parent counts one less.
    private func finish(_ directory: Directory) {
        if unlinkat(self.base, directory.path, AT_REMOVEDIR | AT_SYMLINK_NOFOLLOW_ANY) != 0, errno != ENOENT {
            self.fail()
        }
        directory.parent.map(self.childFinished)
    }

    private func fail() {
        self.failed.store(true, ordering: .relaxed)
    }
}
