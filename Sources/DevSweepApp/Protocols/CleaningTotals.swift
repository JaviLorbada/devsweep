/// What this session's cleans took, which the status line says.
///
/// `CleaningModel` conforms. `OverviewViewModel` takes it.
@MainActor
protocol CleaningTotals: AnyObject {
    /// Moved to the Trash, less what was put back.
    var trashedThisSession: Int64 { get }
    /// Deleted for good, or removed by simctl or brew.
    var deletedThisSession: Int64 { get }
}
