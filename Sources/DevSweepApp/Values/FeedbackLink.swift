import DevSweepKit
import Foundation

/// A link to one of the project's issue forms on GitHub, with what the form
/// asks about the app and the Mac filled in: DevSweep's version and build,
/// the macOS version and the architecture. Nothing else goes in it, no
/// paths and nothing a scan found. Opening it only opens the browser; the
/// person reads the form there and decides whether to submit it.
///
/// GitHub fills a form's field from the query parameter named after the
/// field's `id` in `.github/ISSUE_TEMPLATE`.
struct FeedbackLink: Equatable {
    /// The issue forms, by their files in `.github/ISSUE_TEMPLATE`.
    enum Form: String, CaseIterable {
        case problem = "bug.yml"
        case idea = "idea.yml"

        /// The Help menu's item for it, in title case as menu items are
        /// written, with an ellipsis: the form asks for more.
        var title: String {
            switch self {
            case .problem: "Report a Problem…"
            case .idea: "Suggest an Idea…"
            }
        }
    }

    /// What the forms ask about the app and the Mac, as a person would
    /// type it in.
    struct About: Equatable {
        /// DevSweep's version and build, as the About window writes them:
        /// "0.6.0 (202611141200)".
        let version: String
        /// "26.1 (25B78)".
        let macOS: String
        /// "arm64" or "x86_64".
        let architecture: String
    }

    let form: Form
    let about: About

    /// The form's fields this link fills in, by their ids, in the form's
    /// order. An idea asks only which DevSweep it is for.
    var fields: [(id: String, value: String)] {
        switch self.form {
        case .problem:
            [
                ("devsweep-version", self.about.version),
                ("macos-version", self.about.macOS),
                ("architecture", self.about.architecture),
            ]
        case .idea:
            [("devsweep-version", self.about.version)]
        }
    }

    /// The form, filled in.
    var url: URL {
        ProductInfo.issues.appending(path: "new").appending(
            queryItems: [URLQueryItem(name: "template", value: self.form.rawValue)]
                + self.fields.map { URLQueryItem(name: $0.id, value: $0.value) })
    }
}

extension FeedbackLink.About {
    /// This app, on this Mac.
    static var current: Self {
        let process = ProcessInfo.processInfo
        return Self(
            version: "\(ProductInfo.version) (\(ProductInfo.build))",
            macOS: self.macOS(
                process.operatingSystemVersion,
                build: self.build(fromVersionText: process.operatingSystemVersionString)),
            architecture: self.architecture)
    }

    /// "26.1", or "26.0.1" with a patch, then macOS's build when known:
    /// "26.1 (25B78)". A beta's build tells it from the release.
    static func macOS(_ version: OperatingSystemVersion, build: String?) -> String {
        var text = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 { text += ".\(version.patchVersion)" }
        if let build { text += " (\(build))" }
        return text
    }

    /// The build in macOS's own words for its version, "Version 26.1 (Build
    /// 25B78)": 25B78.
    static func build(fromVersionText text: String) -> String? {
        guard let start = text.range(of: "(Build ")?.upperBound,
              let end = text[start...].firstIndex(of: ")"),
              start < end
        else { return nil }
        return String(text[start..<end])
    }

    /// The architecture this app runs as.
    static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}
