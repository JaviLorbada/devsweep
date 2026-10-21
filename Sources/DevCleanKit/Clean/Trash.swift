import Foundation

/// Moves folders to the Trash and back.
public protocol TrashService: Sendable {
    /// Moves `path` to the Trash and returns where it ended up.
    func trash(_ path: String) throws -> String
    /// Moves an item from the Trash back to `original`.
    func putBack(_ trashed: String, to original: String) throws
}

/// The user's Trash, through `FileManager`, so Finder's Put Back works too.
public struct SystemTrash: TrashService {
    public init() {}

    public func trash(_ path: String) throws -> String {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
        guard let url = resulting as URL? else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url.path(percentEncoded: false)
    }

    public func putBack(_ trashed: String, to original: String) throws {
        try FileManager.default.moveItem(atPath: trashed, toPath: original)
    }
}
