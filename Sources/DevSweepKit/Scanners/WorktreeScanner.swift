import Foundation

/// The linked git worktrees of the repositories in the project folders,
/// wherever the worktrees themselves are: git lists them all, so those a tool
/// keeps in a hidden folder of its own turn up too. A project folder of
/// worktrees works as well: each leads back to its repository, wherever that
/// is. Only worktrees and repositories inside the home folder are listed.
/// Listing changes nothing.
enum WorktreeScanner {
    static func scan(in context: ScanContext) async -> [GitWorktree] {
        let roots = context.policy.projectFolders(context.config.projectDirectories).roots
        let repositories = self.repositories(under: roots, policy: context.policy)
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

    /// The repositories to ask git about, each once: folders holding a `.git`
    /// folder, and for a linked worktree, whose `.git` is a file, the
    /// repository it belongs to, when that is inside the home folder, as
    /// removing a worktree checks. Neither is searched further, nor are
    /// dependency and build folders, where package checkouts would count as
    /// repositories.
    static func repositories(under roots: [String], policy: PathPolicy) -> [String] {
        let library = "\(policy.homeReal)/Library"
        let pruned = ProjectSearch.prunedNames.union([".build"])
        var found: [String] = []
        var seen: Set<String> = []
        for root in roots {
            FileTree.walk(root) { entry in
                if Task.isCancelled { return .stop }
                guard entry.kind == .directory else { return .proceed }
                if entry.path.bytesEqual(library) || pruned.contains(entry.name) { return .skipChildren }
                let dotGit = "\(entry.path)/.git"
                guard !FileSystem.isSymlink(dotGit) else { return .proceed }
                if FileSystem.isDirectory(dotGit) {
                    if seen.insert(entry.path).inserted { found.append(entry.path) }
                    return .skipChildren
                }
                if let repository = self.repository(ofWorktree: entry.path) {
                    if let real = policy.safePath(repository), seen.insert(real).inserted { found.append(real) }
                    return .skipChildren
                }
                return .proceed
            }
        }
        return found
    }

    /// The repository a linked worktree belongs to, from the files git keeps:
    /// the worktree's `.git` file names its folder under the repository's
    /// `worktrees`, whose `commondir` leads back to the repository's git
    /// folder. That is `<repository>/.git`, or the repository itself when it
    /// is bare. Nil for any other `.git` file, a submodule's for one.
    static func repository(ofWorktree folder: String) -> String? {
        guard let line = self.firstLine(of: "\(folder)/.git"), line.hasPrefix("gitdir: ") else { return nil }
        let named = String(line.dropFirst("gitdir: ".count))
        let gitFolder = named.hasPrefix("/") ? named : "\(folder)/\(named)"
        guard FileSystem.basename(FileSystem.dirname(gitFolder)) == "worktrees" else { return nil }
        let common = self.firstLine(of: "\(gitFolder)/commondir")
            .map { $0.hasPrefix("/") ? $0 : "\(gitFolder)/\($0)" }
            ?? FileSystem.dirname(FileSystem.dirname(gitFolder))
        guard let real = FileSystem.physicalDirectory(common) else { return nil }
        return FileSystem.basename(real) == ".git" ? FileSystem.dirname(real) : real
    }

    /// A file's first line, without its line ending.
    private static func firstLine(of path: String) -> String? {
        guard FileSystem.isRegularFile(path), !FileSystem.isSymlink(path),
              let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
            .map { String($0.hasSuffix("\r") ? $0.dropLast() : $0) }
    }

    /// A path under the resolved home folder, as git gives paths, from the
    /// home folder as `HOME` names it instead, so it shortens to `~`. The
    /// two differ when `HOME` goes through a symlink. The prefix is compared
    /// and dropped as bytes: a letter like ö takes two.
    static func fromHome(_ path: String, policy: PathPolicy) -> String {
        guard !policy.home.bytesEqual(policy.homeReal), path.hasBytePrefix(policy.homeReal + "/") else { return path }
        return policy.home + path.removingPrefix(policy.homeReal)
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
