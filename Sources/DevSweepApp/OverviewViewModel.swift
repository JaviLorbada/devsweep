import DevSweepKit
import Observation

/// The overview's own state: the item selected in the chart, the list and
/// the inspector, and the status line under its title.
@MainActor
@Observable
final class OverviewViewModel {
    /// The item the inspector shows; the chart and the list select it.
    var selection: Item?
    private let window: WindowViewModel
    private let scan: ScanModel
    private let cleaning: CleaningModel
    private let apps: RunningAppsModel

    init(window: WindowViewModel, scan: ScanModel, cleaning: CleaningModel, apps: RunningAppsModel) {
        self.window = window
        self.scan = scan
        self.cleaning = cleaning
        self.apps = apps
    }

    /// Selects the biggest item of a family, on the overview.
    func pick(_ family: Family) {
        self.window.screen = .overview
        let tally = self.scan.tally
        if let biggest = tally.live.first(where: { $0.item.family == family }) ?? tally.ordered
            .first(where: { $0.item.family == family })
        {
            self.selection = biggest.item
        }
    }

    /// Selects the biggest item when nothing is selected, as a scan ends.
    func selectFirstIfNone() {
        if self.selection == nil { self.selection = self.scan.tally.ordered.first?.item }
    }

    /// What the scan found, whether Xcode and Simulator are open, and what
    /// this session cleaned.
    var statusLine: String {
        StatusText.overview(
            self.scan.statusFacts,
            runningApps: self.apps.running,
            trashedKilobytes: self.cleaning.trashedThisSession,
            deletedKilobytes: self.cleaning.deletedThisSession)
    }

    /// The status line, and for a development build what it was built
    /// from, so an old bundle can't pass for the latest.
    var subtitle: String {
        [self.statusLine, BuildIdentity.current.statusNote].compactMap(\.self).joined(separator: " ")
    }
}
