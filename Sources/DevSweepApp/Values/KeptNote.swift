import DevSweepKit

/// What a clean's question says of the kept folders it takes, whose git
/// repositories go with them: one by name, several by count.
struct KeptNote {
    /// Each one as a sentence names it: "Ledger/.build holds a git repository, Tool".
    let folders: [String]

    /// The kept folders among `parts` of `result`, in their order.
    init(_ parts: [ItemPart], of result: ItemResult) {
        self.folders = parts.compactMap { part in
            guard case let .folder(path) = part, let folder = result.keptFolder(path) else {
                return nil
            }
            return "\(part.sentenceName(in: result)) \(folder.keptBecause)"
        }
    }

    /// Every kept folder of `results`, cleaned whole.
    init(wholes results: [ItemResult]) {
        self.folders = results.flatMap { result in
            KeptNote((result.kept ?? []).map { .folder($0.path) }, of: result).folders
        }
    }

    /// "Ledger/.build holds a git repository, Tool: its edits and commits go
    /// too."; empty when the clean takes none.
    var text: String {
        switch self.folders.count {
        case 0: ""
        case 1: "\(self.folders[0]): its edits and commits go too."
        default: "\(self.folders.count) folders hold a git repository: their edits and commits go too."
        }
    }
}
