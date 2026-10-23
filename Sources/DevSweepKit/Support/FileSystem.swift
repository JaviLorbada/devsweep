import Darwin

/// Thin wrappers over the POSIX calls the bash script relied on through `test`,
/// `cd -P`, `basename`, `dirname` and globbing, so each check means exactly what
/// it meant there.
enum FileSystem {
    /// `[[ -d path ]]`: a directory, following symlinks.
    static func isDirectory(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    /// `[[ -f path ]]`: a regular file, following symlinks.
    static func isRegularFile(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    /// `[[ -L path ]]`: the path itself is a symlink.
    static func isSymlink(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }

    /// `[[ -e path ]]`: something exists there, following symlinks.
    static func exists(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0
    }

    /// `[[ -e path || -L path ]]`: something exists there, counting broken symlinks.
    static func existsOrIsSymlink(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// Modification time in seconds, of the path itself (`stat -f %m`).
    static func modificationTime(_ path: String) -> Int {
        var info = stat()
        guard lstat(path, &info) == 0 else { return 0 }
        return Int(info.st_mtimespec.tv_sec)
    }

    /// `cd -P -- path && pwd -P`: the directory with every symlink and `..`
    /// resolved, or nil when it isn't a directory you can enter.
    static func physicalDirectory(_ path: String) -> String? {
        guard !path.isEmpty, let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        let real = String(cString: resolved)
        guard self.isDirectory(real), access(real, X_OK) == 0 else { return nil }
        return real
    }

    /// Names inside a directory, without `.` and `..`, in no particular order.
    /// Follows the directory itself when it is a symlink, like a glob does.
    static func childNames(_ directory: String) -> [String] {
        guard let dir = opendir(directory) else { return [] }
        defer { closedir(dir) }
        var names: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name != ".", name != ".." {
                names.append(name)
            }
        }
        return names
    }

    /// The names a bash glob `dir/*` expands to: no hidden names, sorted the
    /// way `LC_ALL=C` sorts them.
    static func globNames(_ directory: String) -> [String] {
        self.childNames(directory).filter { !$0.hasPrefix(".") }.sortedBytewise()
    }

    /// The `basename` utility.
    static func basename(_ path: String) -> String {
        var trimmed = Substring(path)
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed = trimmed.dropLast()
        }
        if trimmed == "/" { return "/" }
        if let slash = trimmed.lastIndex(of: "/") {
            return String(trimmed[trimmed.index(after: slash)...])
        }
        return String(trimmed)
    }

    /// The `dirname` utility.
    static func dirname(_ path: String) -> String {
        var trimmed = Substring(path)
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed = trimmed.dropLast()
        }
        if trimmed == "/" { return "/" }
        guard let slash = trimmed.lastIndex(of: "/") else { return "." }
        var parent = trimmed[..<slash]
        while parent.count > 1, parent.hasSuffix("/") {
            parent = parent.dropLast()
        }
        return parent.isEmpty ? "/" : String(parent)
    }

    /// `fnmatch(3)` without flags, as `find -name` uses it.
    static func matches(_ name: String, pattern: String) -> Bool {
        fnmatch(pattern, name, 0) == 0
    }
}

extension String {
    /// Byte equality, the way bash compares paths. Swift's `==` treats
    /// canonically equivalent strings as equal, which is not what a path check wants.
    func bytesEqual(_ other: String) -> Bool {
        utf8.elementsEqual(other.utf8)
    }

    func hasBytePrefix(_ prefix: String) -> Bool {
        utf8.starts(with: prefix.utf8)
    }

    /// Strips one trailing occurrence of `suffix`, like `${value%suffix}`.
    func removingSuffix(_ suffix: String) -> String {
        guard utf8.count >= suffix.utf8.count, utf8.reversed().starts(with: suffix.utf8.reversed()) else {
            return self
        }
        let bytes = Array(utf8.dropLast(suffix.utf8.count))
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Strips one leading occurrence of `prefix`, like `${value#prefix}`.
    func removingPrefix(_ prefix: String) -> String {
        guard self.hasBytePrefix(prefix) else { return self }
        return String(decoding: Array(utf8.dropFirst(prefix.utf8.count)), as: UTF8.self)
    }

    /// The first `count` bytes, backing off so a character is never split.
    func prefixBytes(_ count: Int) -> String {
        var result = ""
        var used = 0
        for character in self {
            let size = character.utf8.count
            if used + size > count { break }
            result.append(character)
            used += size
        }
        return result
    }
}

extension Sequence<String> {
    /// Sorted by bytes, as `sort` does under `LC_ALL=C`.
    func sortedBytewise() -> [String] {
        sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    /// Sorted by bytes with duplicates removed, as `sort -u` does under `LC_ALL=C`.
    func sortedUniqueBytewise() -> [String] {
        var result: [String] = []
        for path in self.sortedBytewise() where result.last.map({ !$0.bytesEqual(path) }) ?? true {
            result.append(path)
        }
        return result
    }
}
