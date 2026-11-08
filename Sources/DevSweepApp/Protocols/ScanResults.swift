import DevSweepKit

/// What a scan found, as the overview and the marks read it.
///
/// `ScanModel` conforms. `OverviewViewModel` and `MarksModel` take it, so
/// their tests hand them a fake with the rows they need instead of a scan.
@MainActor
protocol ScanResults: AnyObject {
    /// The rows' order, totals and weights.
    var tally: Tally { get }
    /// What the status lines are written from.
    var statusFacts: StatusText.Facts { get }
}
