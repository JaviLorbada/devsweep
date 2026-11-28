import DevSweepKit

/// What is ticked to clean, as a clean reads it and clears what went, and
/// as the inspector's kept folders tick a part.
///
/// `MarksModel` conforms. `CleaningModel` and `KeptFoldersViewModel` take it.
@MainActor
protocol Marking: AnyObject {
    /// The parts of `item` ticked in its inspector.
    func markedParts(of item: Item) -> Set<ItemPart>
    func setMarked(_ part: ItemPart, of item: Item, _ isMarked: Bool)
    /// `item` was cleaned, so it can't be ticked any more.
    func cleaned(_ item: Item)
    /// `parts` of `item` were cleaned, so they can't be ticked any more.
    func cleaned(_ parts: Set<ItemPart>, of item: Item)
}
