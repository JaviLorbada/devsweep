/// Looks for a git repository in a build folder while it is measured. A
/// project's repository ignores its build folders, so it can't see the edits
/// or commits of a dependency cloned into one: a `.git` of any kind (a
/// folder, the file of a worktree or submodule, a symlink) at any depth keeps
/// the folder.
struct RepositorySearch: Sendable {
    /// Whether the clones SwiftPM makes while it resolves packages, and Xcode
    /// through it, don't count. Each sits in a `checkouts` folder next to the
    /// `repositories` it was cloned from, wherever the build put the pair:
    /// in `.build`, in SourceKit-LSP's `.build/index-build`, or in the
    /// `SourcePackages` of any folder Xcode builds into. Resolving the
    /// packages clones them again at the commits `Package.resolved` pins.
    let skipsPackageClones: Bool

    init(skipsPackageClones: Bool = false) {
        self.skipsPackageClones = skipsPackageClones
    }

    /// The repository `entry` is the `.git` of, when it counts: the folder
    /// holding it.
    func repository(at entry: FileTree.Entry, in folder: String) -> String? {
        guard entry.name == ".git" else {
            return nil
        }
        if self.skipsPackageClones, self.isInPackageClone(entry.path, in: folder) {
            return nil
        }
        return FileSystem.dirname(entry.path)
    }

    /// Whether `path`, below its repository's folder, sits in a `checkouts`
    /// folder inside `folder` that has `repositories` next to it.
    private func isInPackageClone(_ path: String, in folder: String) -> Bool {
        var current = FileSystem.dirname(FileSystem.dirname(path))
        while current.hasBytePrefix("\(folder)/") {
            let parent = FileSystem.dirname(current)
            if FileSystem.basename(current).bytesEqual("checkouts"),
               FileSystem.isDirectory("\(parent)/repositories")
            {
                return true
            }
            current = parent
        }
        return false
    }
}
