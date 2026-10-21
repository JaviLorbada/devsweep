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

/// A Trash that is just a folder: items move into it under their own name,
/// numbered when the name is taken. For tests, and for trying the app
/// against a fake home without filling the real Trash.
public struct FolderTrash: TrashService {
    public let folder: String

    public init(folder: String) {
        self.folder = folder
    }

    public func trash(_ path: String) throws -> String {
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let name = FileSystem.basename(path)
        var destination = "\(folder)/\(name)"
        var counter = 1
        while FileSystem.existsOrIsSymlink(destination) {
            counter += 1
            destination = "\(folder)/\(name) \(counter)"
        }
        try FileManager.default.moveItem(atPath: path, toPath: destination)
        return destination
    }

    public func putBack(_ trashed: String, to original: String) throws {
        try FileManager.default.moveItem(atPath: trashed, toPath: original)
    }
}
