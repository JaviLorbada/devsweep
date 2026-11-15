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
    var kilobytes: Int64 = 0
    /// Parts of the item to clean instead of the whole of it.
    var parts: Set<ItemPart> = []
    /// What the question calls those parts: "DerivedData for Atlas",
    /// "App-1/.build and App-2/.build", "5 .build folders".
    var partsSubject = ""
    /// Whether that subject takes "go" rather than "goes".
    var partsPlural = false
    /// Those of them that need Xcode closed, by name.
    var blockedPartNames: [String] = []
    /// Asked while Xcode is open, which may have the project open.
    var xcodeOpen = false
    /// The project to close in Xcode, for one part; empty for several.
    var xcodeName = ""

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
