import DevSweepKit
import Observation

/// The inspector's Kept list: the build folders a scan kept because each
/// holds a git repository, and ticking one to clean it, which nothing else
/// does.
@MainActor
@Observable
final class KeptFoldersViewModel {
    /// One kept folder, as the list shows it.
    struct Line: Identifiable {
        /// What ticking it cleans.
        let part: ItemPart
        /// The project it belongs to: "ferris".
        let name: String
        /// Where it is, with a `~`.
        let path: String
        let size: String
        /// "Holds a git repository, chart-kit".
        let reason: String

        var id: ItemPart {
            self.part
        }
    }

    private let scan: any ScanResults
    private let marks: any Marking

    init(scan: any ScanResults, marks: any Marking) {
        self.scan = scan
        self.marks = marks
    }

    /// `item`'s kept folders once a scan measured them: this scan's, or the
    /// last one's while this one waits to reach it.
    func lines(of item: Item) -> [Line] {
        guard let row = self.row(of: item), row.wasMeasured || row.showsPrevious,
              let kept = row.shownResult?.kept
        else {
            return []
        }
        let names = PartsList.folderNames(kept.map(\.path))
        return kept.map { folder in
            Line(
                part: .folder(folder.path),
                name: names[folder.path] ?? folder.path,
                path: self.scan.tilde(folder.path),
                size: SizeText.of(kilobytes: folder.kilobytes),
                reason: folder.reason)
        }
    }

    /// Whether `item`'s kept folders can be ticked: this scan's, not the last one's.
    func showsTicks(for item: Item) -> Bool {
        guard let row = self.row(of: item) else {
            return false
        }
        return row.result != nil && [.measured, .cleaning].contains(row.state)
    }

    /// Ticks wait while a scan or a clean runs.
    var canTick: Bool {
        !self.scan.statusFacts.isScanning && !self.scan.isCleaning
    }

    func isMarked(_ line: Line, of item: Item) -> Bool {
        self.marks.markedParts(of: item).contains(line.part)
    }

    func setMarked(_ line: Line, of item: Item, _ isMarked: Bool) {
        self.marks.setMarked(line.part, of: item, isMarked)
    }

    private func row(of item: Item) -> ScanRow? {
        self.scan.tally.rows.first { $0.item == item }
    }
}
