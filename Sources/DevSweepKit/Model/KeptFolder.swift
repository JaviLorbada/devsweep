/// A build folder kept because it holds a git repository: the project's
/// repository ignores the folder, so it can't see that clone's edits or
/// commits. It is measured like the folders the item lists, but not counted.
public struct KeptFolder: Sendable, Equatable, Codable {
    /// The folder, resolved.
    public let path: String
    /// The first repository the walk found: the folder itself, or one inside it.
    public let repository: String
    /// Its size, as `du -sk` prints it.
    public let kilobytes: Int64

    public init(path: String, repository: String, kilobytes: Int64) {
        self.path = path
        self.repository = repository
        self.kilobytes = kilobytes
    }

    /// Where the repository sits in the folder, "lib/dependency"; nil when
    /// the folder is the repository.
    public var repositoryInside: String? {
        self.repository.bytesEqual(self.path) ? nil : self.repository.removingPrefix("\(self.path)/")
    }
}
