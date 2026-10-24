import Foundation

/// Which build this is, as `Scripts/package_app.sh` writes it into the
/// bundle's Info.plist: the commit, whether the tree had uncommitted changes,
/// and whether the bundle is signed for release. Outside a packaged bundle,
/// as `swift run` starts the app, nothing is known.
public struct BuildIdentity: Equatable, Sendable {
    public var commit: String?
    public var builtWithChanges: Bool
    public var releaseSigned: Bool

    public static let current = BuildIdentity(info: Bundle.main.infoDictionary ?? [:])

    public init(info: [String: Any]) {
        self.commit = (info["DevSweepCommit"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.builtWithChanges = info["DevSweepTreeDirty"] as? Bool ?? false
        self.releaseSigned = info["DevSweepReleaseSigned"] as? Bool ?? false
    }

    /// "506cc8c", "506cc8c with uncommitted changes", or nil when unknown.
    public var commitDescription: String? {
        self.commit.map { self.builtWithChanges ? "\($0) with uncommitted changes" : $0 }
    }

    /// "Built from 506cc8c.", for the status line of a build not signed for
    /// release, so a development build can be told apart at a glance.
    public var statusNote: String? {
        guard !self.releaseSigned else { return nil }
        return self.commitDescription.map { "Built from \($0)." }
    }
}
