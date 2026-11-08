import DevSweepKit

/// What a scan lists besides the items: the Xcodes, runtimes and worktrees,
/// and what Android Studio keeps. Removing a runtime or a worktree lists
/// them again.
///
/// `ScanModel` conforms. The Xcodes, runtimes, worktrees and Android view
/// models take it.
@MainActor
protocol Listings: AnyObject {
    /// Installed Xcodes, runtimes and worktrees.
    var extras: Extras? { get }
    /// What Android Studio keeps.
    var android: AndroidReport? { get }
    var isLoadingExtras: Bool { get }
    var isLoadingAndroid: Bool { get }
    /// The path rule, which writes paths the way the window shows them.
    var policy: PathPolicy? { get }
    /// Removes a runtime through simctl. Whether simctl removed it.
    func removeRuntime(_ runtime: SimulatorRuntime) async -> Bool
    /// Removes a worktree with git. Whether git removed it.
    func removeWorktree(_ worktree: GitWorktree) async -> Bool
}
