import Darwin

/// Why devclean refuses to start. The messages are the bash script's, word for word.
public enum PreflightError: Error, Sendable, Equatable, CustomStringConvertible {
    case runningAsRoot
    case badHome
    case unknownItem(String)

    public var description: String {
        switch self {
        case .runningAsRoot:
            "Don't run devclean with sudo. Everything it cleans belongs to your user."
        case .badHome:
            "HOME must be your home folder."
        case .unknownItem(let id):
            "Unknown item '\(id)'. Items: \(Item.idList)"
        }
    }
}

/// The rule every path passes before devclean lists it and again right before
/// it deletes it: a directory, not itself a symlink, whose fully resolved form
/// is strictly inside the resolved home folder.
public struct PathPolicy: Sendable {
    /// `$HOME` as given.
    public let home: String
    /// `$HOME` with symlinks and `..` resolved, once.
    public let homeReal: String

    /// Resolves the home folder. Fails unless `home` is an absolute path to a
    /// directory other than `/`.
    public init(home: String) throws(PreflightError) {
        guard home.hasPrefix("/"), home.utf8.count > 1, FileSystem.isDirectory(home),
              let real = FileSystem.physicalDirectory(home), real.hasPrefix("/"), real.utf8.count > 1
        else {
            throw .badHome
        }
        self.home = home
        self.homeReal = real
    }

    /// The checks the script runs before anything else: not root, and a usable home.
    public static func preflight(home: String, effectiveUserID: uid_t = geteuid()) throws(PreflightError) -> PathPolicy {
        guard effectiveUserID != 0 else { throw .runningAsRoot }
        return try PathPolicy(home: home)
    }

    /// The resolved path of `path` if it may be acted on, nil otherwise.
    public func safePath(_ path: String) -> String? {
        guard FileSystem.isDirectory(path), !FileSystem.isSymlink(path),
              let real = FileSystem.physicalDirectory(path), isStrictlyInsideHome(real)
        else {
            return nil
        }
        return real
    }

    /// The same check as `safePath`, asked of a resolved path right before it
    /// is deleted: it must still resolve to exactly itself.
    public func stillSafe(_ resolved: String) -> Bool {
        safePath(resolved)?.bytesEqual(resolved) ?? false
    }

    public func isStrictlyInsideHome(_ real: String) -> Bool {
        real.hasBytePrefix(homeReal + "/") && real.utf8.count > homeReal.utf8.count + 1
    }

    /// The home folder itself or anything inside it.
    public func isInsideOrHome(_ real: String) -> Bool {
        real.bytesEqual(homeReal) || real.hasBytePrefix(homeReal + "/")
    }

    /// Shortens a path under `$HOME` to `~/...`, comparing against `$HOME` as given.
    public func tilde(_ path: String) -> String {
        if path.bytesEqual(home) { return "~" }
        if path.hasBytePrefix(home + "/") {
            return "~" + String(decoding: path.utf8.dropFirst(home.utf8.count), as: UTF8.self)
        }
        return path
    }

    /// Replaces a leading `~` with `$HOME`, like `${path/#\~/$HOME}`.
    public func expandTilde(_ path: String) -> String {
        guard path.utf8.first == UInt8(ascii: "~") else { return path }
        return home + String(decoding: path.utf8.dropFirst(), as: UTF8.self)
    }

    public enum ProjectFolder: Sendable, Equatable {
        case missing
        case outside
        case inside(String)
    }

    /// Where a project folder really is. The home folder itself counts as inside.
    public func resolveProjectFolder(_ entry: String) -> ProjectFolder {
        guard let real = FileSystem.physicalDirectory(expandTilde(entry)) else { return .missing }
        return isInsideOrHome(real) ? .inside(real) : .outside
    }

    /// Sorts project folder entries into found, missing and outside home.
    public func projectFolders(_ entries: [String]) -> ProjectFolders {
        var folders = ProjectFolders()
        for entry in entries where !entry.isEmpty {
            let shown = tilde(expandTilde(entry))
            switch resolveProjectFolder(entry) {
            case .missing: folders.missing.append(shown)
            case .outside: folders.outside.append(shown)
            case .inside(let real):
                folders.found.append(shown)
                folders.roots.append(real)
            }
        }
        return folders
    }
}
