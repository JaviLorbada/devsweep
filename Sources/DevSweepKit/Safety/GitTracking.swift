/// Build folders are deleted only when git provably tracks nothing in them.
enum GitTracking {
    /// True only when it's certain git tracks nothing in `folder`: no git
    /// repository contains it, or git answers that none of its files are
    /// tracked. If git can't answer (corrupt index, unsafe ownership, a `.git`
    /// symlink to a missing disk, git missing), warns and returns false so the
    /// folder is kept.
    static func isUntracked(
        _ folder: String,
        environment: [String: String],
        git: any GitClient,
        policy: PathPolicy,
        warn: (String) -> Void) async -> Bool
    {
        let parent = FileSystem.dirname(folder)

        // Shortcut: no repository can contain the folder when git isn't pointed
        // at one through the environment and no parent has a .git entry,
        // counting .git symlinks whose target is missing.
        if (environment["GIT_DIR"] ?? "").isEmpty, (environment["GIT_WORK_TREE"] ?? "").isEmpty {
            var probe = parent
            while !FileSystem.existsOrIsSymlink("\(probe)/.git") {
                if probe == "/" { return true }
                probe = FileSystem.dirname(probe)
            }
        }

        guard let tracked = await git.trackedFiles(in: parent, named: FileSystem.basename(folder)) else {
            warn("Skipped \(policy.tilde(folder)): couldn't check whether git tracks it.")
            return false
        }
        return tracked.isEmpty
    }
}
