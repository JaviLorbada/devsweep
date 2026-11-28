import DevSweepKit

/// The words the inspector uses for a build folder the scan kept.
extension KeptFolder {
    /// Why it was kept: "Holds a git repository, chart-kit".
    var reason: String {
        self.repositoryInside.map { "Holds a git repository, \($0)" } ?? "Is a git repository"
    }
}
