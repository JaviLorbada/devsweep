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

    static let prunedNames: Set<String> = [".git", "node_modules", "Pods", "DerivedData"]

    init(roots: [String], homeReal: String) {
        self.roots = roots
        self.library = "\(homeReal)/Library"
    }

    func folders(named name: String) async -> [String] {
        let search = self.searches[name] ?? {
            let roots = roots, library = library
            let search = Task { Self.walk(roots: roots, library: library, name: name) }
            self.searches[name] = search
            return search
        }()
        return await withTaskCancellationHandler { await search.value } onCancel: { search.cancel() }
    }

    private static func walk(roots: [String], library: String, name: String) -> [String] {
        var found: [String] = []
        for root in roots {
            FileTree.walk(root) { entry in
                if Task.isCancelled { return .stop }
                if entry.path.bytesEqual(library) || self.prunedNames.contains(entry.name) {
                    return .skipChildren
                }
                if entry.kind == .directory || entry.kind == .unreadable, entry.name == name {
                    found.append(entry.path)
                    return .skipChildren
                }
                return .proceed
            }
        }
        return found
    }
}
