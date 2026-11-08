import DevSweepKit

/// The scan's rows as a clean changes them: the lock that keeps a scan and a
/// clean apart, and each row as it is cleaned or put back. A clean takes the
/// rows with `beginCleaning()`, which hands it the `Cleaner`, and gives them
/// back with `endCleaning(warnings:)`.
///
/// `ScanModel` conforms, and only it changes the rows. `CleaningModel`
/// takes it.
@MainActor
protocol ScanRows: AnyObject {
    var rows: [Item: ScanRow] { get }
    var isScanning: Bool { get }
    var isCleaning: Bool { get }

    /// Takes the rows for a clean or a put back, and hands back what does
    /// it: nil while scanning or cleaning, or with no home to clean in.
    func beginCleaning() -> (any Cleaner)?
    /// Gives the rows back, with the free space measured again and the
    /// results kept for the next launch; `warnings` join the scan's.
    func endCleaning(warnings: [String])
    /// `item`'s row starts cleaning; `kilobytes` is what it will take, when
    /// only parts of it go.
    func startCleaning(_ item: Item, kilobytes: Int64?)
    /// While deleting, how much of `item` is gone so far.
    func cleaningProgress(_ item: Item, removedBytes: Int64)
    /// The whole of `item` went, with `outcome`; nil when nothing was removed.
    func finishCleaning(_ item: Item, outcome: CleanOutcome?)
    /// Parts of `item` went, and `left` is what remains of it.
    func finishCleaningParts(_ item: Item, left: ItemResult)
    /// What cleaning `item` moved to the Trash came back.
    func putBack(_ item: Item)
    /// Parts of `item` came back from the Trash, and it is `whole` again.
    func putBackParts(_ item: Item, whole: ItemResult)
    /// `path` with the home folder as `~`.
    func tilde(_ path: String) -> String
}
