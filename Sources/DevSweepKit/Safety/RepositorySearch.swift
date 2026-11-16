/// Looks for a git repository in a build folder while it is measured. A
/// project's repository ignores its build folders, so it can't see the edits
/// or commits of a dependency cloned into one: a `.git` of any kind (a
/// folder, the file of a worktree or submodule, a symlink) at any depth keeps
/// the folder.
struct RepositorySearch: Sendable {
    /// Folders, relative to the build folder, whose clones a package manager
    /// makes again by itself, like SwiftPM's `checkouts` and `repositories`,
    /// which `swift package resolve` clones again at the commits
    /// `Package.resolved` pins. A `.git` in them doesn't count.
    let managedFolders: [String]

    init(managedFolders: [String] = []) {
        self.managedFolders = managedFolders
    }

    /// The repository `entry` is the `.git` of, when it counts: the folder
    /// holding it.
    func repository(at entry: FileTree.Entry, in folder: String) -> String? {
        guard entry.name == ".git" else {
            return nil
        }
        let managed = self.managedFolders.contains { entry.path.hasBytePrefix("\(folder)/\($0)/") }
        return managed ? nil : FileSystem.dirname(entry.path)
    }
}
