import Foundation

/// The linked git worktrees of the repositories in the project folders,
/// wherever the worktrees themselves are: git lists them all, so those a tool
/// keeps in a hidden folder of its own turn up too. Only worktrees inside the
/// home folder are listed. Listing changes nothing.
enum WorktreeScanner {
    static func scan(in context: ScanContext) async -> [GitWorktree] {
        let roots = context.policy.projectFolders(context.config.projectDirectories).roots
        let repositories = self.repositories(under: roots, library: "\(context.policy.homeReal)/Library")
        var seen: Set<String> = []
        var worktrees: [GitWorktree] = []
        for repository in repositories {
            if Task.isCancelled { break }
            guard let listing = await context.tools.git.worktreeList(in: repository) else { continue }
            // The first entry is always the repository's main working copy.
            for entry in self.parse(listing).dropFirst() where !entry.isPrunable {
                guard let real = context.policy.safePath(entry.path), seen.insert(real).inserted else { continue }
                await worktrees.append(self.describe(
                    entry,
                    real: real,
                    repository: self.fromHome(repository, policy: context.policy),
                    in: context))
            }
        }
        return worktrees.sorted { $0.kilobytes > $1.kilobytes }
    }

    /// Folders holding a `.git` folder: repositories with a working copy.
    /// A repository's own folders aren't searched further, nor dependency and
    /// build folders, where package checkouts would count as repositories.
    static func repositories(under roots: [String], library: String) -> [String] {
        let pruned = ProjectSearch.prunedNames.union([".build"])
        var found: [String] = []
        for root in roots {
            FileTree.walk(root) { entry in
                if Task.isCancelled { return .stop }
                guard entry.kind == .directory else { return .proceed }
                if entry.path.bytesEqual(library) || pruned.contains(entry.name) { return .skipChildren }
                if FileSystem.isDirectory("\(entry.path)/.git"), !FileSystem.isSymlink("\(entry.path)/.git") {
                    found.append(entry.path)
                    return .skipChildren
                }
                return .proceed
            }
        }
        return found
    }

    /// A path under the resolved home folder, as git gives paths, from the
    /// home folder as `HOME` names it instead, so it shortens to `~`. The
    /// two differ when `HOME` goes through a symlink.
    static func fromHome(_ path: String, policy: PathPolicy) -> String {
        guard !policy.home.bytesEqual(policy.homeReal), path.hasBytePrefix(policy.homeReal + "/") else { return path }
        return policy.home + path.dropFirst(policy.homeReal.utf8.count)
    }

    /// One entry of `git worktree list --porcelain`.
    struct Entry: Equatable {
        var path: String
        /// The branch's short name, nil when HEAD is detached.
        var branch: String?
        var isLocked = false
        /// Its folder is gone; `git worktree prune` would forget it.
        var isPrunable = false
    }

    /// Entries are separated by blank lines; each starts with `worktree <path>`.
    static func parse(_ listing: String) -> [Entry] {
        var entries: [Entry] = []
        for line in listing.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("worktree ") {
                entries.append(Entry(path: String(line.dropFirst("worktree ".count))))
            } else if !entries.isEmpty {
                if line.hasPrefix("branch ") {
                    let reference = line.dropFirst("branch ".count)
                    entries[entries.count - 1].branch = String(
                        reference.hasPrefix("refs/heads/") ? reference.dropFirst("refs/heads/".count) : reference)
                } else if line == "locked" || line.hasPrefix("locked ") {
                    entries[entries.count - 1].isLocked = true
                } else if line == "prunable" || line.hasPrefix("prunable ") {
                    entries[entries.count - 1].isPrunable = true
                }
            }
        }
        return entries
    }

    static func describe(
        _ entry: Entry,
        real: String,
        repository: String,
        in context: ScanContext) async -> GitWorktree
    {
        let git = context.tools.git
        let status = await git.status(in: entry.path)
        let refs = await git.refsContainingHead(in: entry.path)
        let time = await git.headCommitTime(in: entry.path)
        return await GitWorktree(
            path: self.fromHome(entry.path, policy: context.policy),
            repository: repository,
            branch: entry.branch,
            kilobytes: context.measurer.measureOffPool(real).kilobytes,
            lastCommit: time.flatMap { TimeInterval($0) }.map { Date(timeIntervalSince1970: $0) },
            changes: status.map { $0.split(separator: "\n").count },
            commitsKept: entry.branch != nil || !(refs ?? "").isEmpty,
            isLocked: entry.isLocked)
    }
}
