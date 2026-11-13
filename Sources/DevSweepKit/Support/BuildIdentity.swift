import Foundation

/// Which build this is, as `Scripts/package_app.sh` writes it into the
/// bundle's Info.plist: the commit, whether the tree had uncommitted changes,
/// and whether the bundle is signed for release. Outside a packaged bundle,
/// as `swift run` starts the app, nothing is known.
public struct BuildIdentity: Equatable, Sendable {
    public var commit: String?
    public var builtWithChanges: Bool
    public var releaseSigned: Bool
    /// Packaged for development rather than for people to download: it runs
    /// beside the released app under its own name, settings and data.
    public var isDevelopment: Bool

    public static let current = BuildIdentity(info: Bundle.main.infoDictionary ?? [:])

    public init(info: [String: Any]) {
        self.commit = (info["DevSweepCommit"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.builtWithChanges = info["DevSweepTreeDirty"] as? Bool ?? false
        self.releaseSigned = info["DevSweepReleaseSigned"] as? Bool ?? false
        self.isDevelopment = info["DevSweepDevelopment"] as? Bool ?? false
    }

    /// "DevSweep", or "DevSweep Dev" for a development build, as its bundle
    /// is named, in About and the app menu.
    public var appName: String {
        self.isDevelopment ? "\(ProductInfo.name) Dev" : ProductInfo.name
    }

    /// The folder in `~/Library/Application Support` the app keeps its last
    /// scan in, named like the app, so a development build never reads or
    /// replaces the released app's.
    public var supportFolder: String {
        self.appName
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
