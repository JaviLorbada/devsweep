import DevSweepKit
import Foundation

/// A clean waiting on an answer: quit Xcode first, or confirm.
struct PendingClean: Identifiable {
    enum Stage {
        case quitApps([DeveloperApp])
        case confirm
    }

    let id = UUID()
    let items: [Item]
    let stage: Stage
    /// What the clean would take, as the scan measured it: the items, or
    /// just the parts.
    let kilobytes: Int64
    /// Parts of the item to clean instead of the whole of it.
    let parts: Set<ItemPart>
    /// What the question calls those parts: "DerivedData for Atlas",
    /// "App-1/.build and App-2/.build", "5 .build folders".
    let partsSubject: String
    /// Whether that subject takes "go" rather than "goes".
    let partsPlural: Bool
    /// Those of them that need Xcode closed, by name.
    let blockedPartNames: [String]
    /// Asked while Xcode is open, which may have the project open.
    let xcodeOpen: Bool
    /// The project to close in Xcode, for one part; empty for several.
    let xcodeName: String
    /// What goes with the kept folders among the parts: "Ledger/.build
    /// holds a git repository, Tool: its edits and commits go too."
    let keptNote: String

    init(
        items: [Item],
        stage: Stage,
        kilobytes: Int64 = 0,
        parts: Set<ItemPart> = [],
        partsSubject: String = "",
        partsPlural: Bool = false,
        blockedPartNames: [String] = [],
        xcodeOpen: Bool = false,
        xcodeName: String = "",
        keptNote: String = "")
    {
        self.items = items
        self.stage = stage
        self.kilobytes = kilobytes
        self.parts = parts
        self.partsSubject = partsSubject
        self.partsPlural = partsPlural
        self.blockedPartNames = blockedPartNames
        self.xcodeOpen = xcodeOpen
        self.xcodeName = xcodeName
        self.keptNote = keptNote
    }

    /// What of it can be cleaned with Xcode and Simulator open: some of the
    /// items, or some of the parts; nil when none of it can.
    var others: (items: [Item], parts: Set<ItemPart>)? {
        if let item = self.items.first, !self.parts.isEmpty {
            let parts = self.parts.filter { !$0.needsXcodeClosed(in: item) }
            return parts.isEmpty ? nil : (self.items, parts)
        }
        let items = self.items.filter { !$0.needsXcodeClosed }
        return items.isEmpty ? nil : (items, [])
    }

    /// Whether some of it can be cleaned with Xcode and Simulator open.
    var hasOthers: Bool {
        self.others != nil
    }
}

extension PendingClean {
    /// The question about cleaning `items` whole, as big as their `rows`.
    init(items: [Item], stage: Stage, rows: [Item: ScanRow]) {
        self.init(items: items, stage: stage, kilobytes: items.compactMap { rows[$0]?.kilobytes }.reduce(0, +))
    }
}
