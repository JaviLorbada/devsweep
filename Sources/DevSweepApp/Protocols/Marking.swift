import DevSweepKit

/// What is ticked to clean, as a clean reads it and clears what went.
///
/// `MarksModel` conforms. `CleaningModel` takes it.
@MainActor
protocol Marking: AnyObject {
    /// The parts of `item` ticked in its inspector.
    func markedParts(of item: Item) -> Set<ItemPart>
    /// `item` was cleaned, so it can't be ticked any more.
    func cleaned(_ item: Item)
    /// `parts` of `item` were cleaned, so they can't be ticked any more.
    func cleaned(_ parts: Set<ItemPart>, of item: Item)
}
