/// Finds folders by name in the project folders, once per name. It never
/// follows symlinks, and never descends into a match, `~/Library` or a
/// pruned folder.
///
/// Run under the original script's name it is the script's `find ROOT \(
/// -path ~/Library -o -name .git -o -name node_modules -o -name Pods -o -name
/// DerivedData \) -prune -o -type d -name NAME -prune -print`. As devsweep it
/// also keeps out of every other build folder, so a folder inside another,
/// like a node_modules in Gradle's build folder, counts only as part of it.
actor ProjectSearch {
    let roots: [String]
    let library: String
    /// Never descended into. A search for one of them still finds it.
    let pruned: Set<String>
    /// One search per name; a second caller for the same name waits for the
    /// first, while searches for other names run at the same time.
    private var searches: [String: Task<[String], Never>] = [:]

    /// What the bash script's find never descends into.
    static let prunedNames: Set<String> = [".git", "node_modules", "Pods", "DerivedData"]

    /// Folders of build output and installed packages: the ones the searches
    /// look for, and Python's `.venv`, which no item lists but whose insides
    /// belong to it.
    static let buildFolderNames: Set<String> = [".build", "build", "target", ".venv", "node_modules", "Pods"]

    init(roots: [String], homeReal: String, outermostBuildFolders: Bool = true) {
        self.roots = roots
        self.library = "\(homeReal)/Library"
        self.pruned = outermostBuildFolders ? Self.prunedNames.union(Self.buildFolderNames) : Self.prunedNames
    }

    func folders(named name: String) async -> [String] {
        let search = self.searches[name] ?? {
            let roots = roots, library = library, pruned = pruned
            let search = Task {
                Self.walk(roots: roots, library: library, pruned: pruned, name: name)
            }
            self.searches[name] = search
            return search
        }()
        return await withTaskCancellationHandler { await search.value } onCancel: { search.cancel() }
    }

    private static func walk(roots: [String], library: String, pruned: Set<String>, name: String) -> [String] {
        var found: [String] = []
        for root in roots {
            FileTree.walk(root) { entry in
                if Task.isCancelled {
                    return .stop
                }
                if entry.path.bytesEqual(library) {
                    return .skipChildren
                }
                if entry.kind == .directory || entry.kind == .unreadable, entry.name == name {
                    found.append(entry.path)
                    return .skipChildren
                }
                return pruned.contains(entry.name) ? .skipChildren : .proceed
            }
        }
        return found
    }
}
