/// Finds folders by name in the project folders, once per name.
///
/// Like `find ROOT \( -path ~/Library -o -name .git -o -name node_modules -o
/// -name Pods -o -name DerivedData \) -prune -o -type d -name NAME -prune -print`:
/// never follows symlinks, never descends into a match.
actor ProjectSearch {
    let roots: [String]
    let library: String
    /// One search per name; a second caller for the same name waits for the
    /// first, while searches for other names run at the same time.
    private var searches: [String: Task<[String], Never>] = [:]

    /// Never descended into, as by the bash script's find. A search for one
    /// of them still finds it.
    static let prunedNames: Set<String> = [".git", "node_modules", "Pods", "DerivedData"]

    /// Folders other languages' tools fill with installed packages and build
    /// output. A search for one never descends into any of them, so one
    /// inside another, like a package's own node_modules in a Python
    /// environment, is never listed: it belongs to the folder around it.
    static let toolFolderNames: Set<String> = ["node_modules", ".venv", "target", "Pods"]

    init(roots: [String], homeReal: String) {
        self.roots = roots
        self.library = "\(homeReal)/Library"
    }

    func folders(named name: String) async -> [String] {
        let search = self.searches[name] ?? {
            let roots = roots, library = library
            let search = Task {
                Self.walk(roots: roots, library: library, name: name)
            }
            self.searches[name] = search
            return search
        }()
        return await withTaskCancellationHandler { await search.value } onCancel: { search.cancel() }
    }

    private static func walk(roots: [String], library: String, name: String) -> [String] {
        let isToolFolder = self.toolFolderNames.contains(name)
        let pruned = isToolFolder ? self.prunedNames.union(self.toolFolderNames) : self.prunedNames
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
