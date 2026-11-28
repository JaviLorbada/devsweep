import DevSweepKit

/// The words the window uses for a build folder the scan kept.
extension KeptFolder {
    /// Why it was kept, after its name: "holds a git repository, chart-kit".
    var keptBecause: String {
        self.repositoryInside.map { "holds a git repository, \($0)" } ?? "is a git repository"
    }

    /// Why it was kept, on a line of its own: "Holds a git repository, chart-kit".
    var reason: String {
        self.keptBecause.prefix(1).uppercased() + self.keptBecause.dropFirst()
    }
}
