import DevSweepKit

/// What cleans the home scanned and puts back what went to the Trash: the
/// kit's `Engine`, as a clean sees it. A clean gets one only by taking the
/// rows, from `ScanRows.beginCleaning()`, so nothing is cleaned or put back
/// while a scan or another clean runs.
///
/// `Engine` conforms. `CleaningModel` uses it; its tests hand it a fake that
/// never touches the disk.
protocol Cleaner: Sendable {
    /// Cleans one scanned item, to the Trash or for good. `progress` gets the
    /// bytes removed so far, from any thread.
    func clean(_ result: ItemResult, mode: CleanMode, progress: (@Sendable (Int64) -> Void)?) async -> CleanOutcome
    /// Cleans some parts of a scanned item: some of its folders, or parts of DerivedData.
    func clean(
        _ parts: Set<ItemPart>,
        of result: ItemResult,
        mode: CleanMode,
        progress: (@Sendable (Int64) -> Void)?) async -> PartsCleanOutcome
    /// Moves what a clean put in the Trash back where it was.
    func putBack(_ outcome: CleanOutcome) async -> PutBackOutcome
}

extension Engine: Cleaner {}
