/// Finds folders by name in the project folders, once per name.
///
/// Like `find ROOT \( -path ~/Library -o -name .git -o -name node_modules -o
/// -name Pods -o -name DerivedData \) -prune -o -type d -name NAME -prune -print`:
/// never follows symlinks, never descends into a match.
actor ProjectSearch {
    let roots: [String]
    let library: String
    private var cache: [String: [String]] = [:]

    static let prunedNames: Set<String> = [".git", "node_modules", "Pods", "DerivedData"]

    init(roots: [String], homeReal: String) {
        self.roots = roots
        self.library = "\(homeReal)/Library"
    }

    func folders(named name: String) -> [String] {
        if let cached = cache[name] { return cached }
        var found: [String] = []
        for root in roots {
            FileTree.walk(root) { entry in
                if Task.isCancelled { return .stop }
                if entry.path.bytesEqual(library) || Self.prunedNames.contains(entry.name) {
                    return .skipChildren
                }
                if entry.kind == .directory || entry.kind == .unreadable, entry.name == name {
                    found.append(entry.path)
                    return .skipChildren
                }
                return .proceed
            }
        }
        cache[name] = found
        return found
    }
}
