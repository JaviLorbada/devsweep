import DevSweepKit

/// What a scan found, as the overview, the marks and the kept folders read it.
///
/// `ScanModel` conforms. `OverviewViewModel`, `MarksModel` and
/// `KeptFoldersViewModel` take it, so their tests hand them a fake with the
/// rows they need instead of a scan.
@MainActor
protocol ScanResults: AnyObject {
    /// The rows' order, totals and weights.
    var tally: Tally { get }
    /// What the status lines are written from.
    var statusFacts: StatusText.Facts { get }
    /// Whether a clean holds the rows.
    var isCleaning: Bool { get }
    /// `path` with the home folder as `~`.
    func tilde(_ path: String) -> String
}
