import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

@Suite("Feedback links")
struct FeedbackLinkTests {
    let about = FeedbackLink.About(version: "0.6.0 (202611141200)", macOS: "26.1 (25B78)", architecture: "arm64")

    /// The query's names and values, in order.
    func query(_ url: URL) -> [String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.map { "\($0.name)=\($0.value ?? "")" }
    }

    @Test
    func `a problem's form is filled in with the versions and the architecture, and nothing else`() {
        let url = FeedbackLink(form: .problem, about: self.about).url
        #expect(url.absoluteString == "https://github.com/JaviLorbada/devsweep/issues/new?template=bug.yml"
            + "&devsweep-version=0.6.0%20(202611141200)&macos-version=26.1%20(25B78)&architecture=arm64")
        #expect(self.query(url) == [
            "template=bug.yml",
            "devsweep-version=0.6.0 (202611141200)",
            "macos-version=26.1 (25B78)",
            "architecture=arm64",
        ])
    }

    @Test
    func `an idea's form is filled in with DevSweep's version alone`() {
        let url = FeedbackLink(form: .idea, about: self.about).url
        #expect(url.absoluteString.hasPrefix(ProductInfo.issues.absoluteString + "/new?"))
        #expect(self.query(url) == ["template=idea.yml", "devsweep-version=0.6.0 (202611141200)"])
    }

    @Test
    func `the forms on GitHub have a text field for each value a link fills in`() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for form in FeedbackLink.Form.allCases {
            let file = root.appending(path: ".github/ISSUE_TEMPLATE/\(form.rawValue)")
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map(String.init)
            for field in FeedbackLink(form: form, about: self.about).fields {
                // GitHub fills text fields from the query; a dropdown it may not.
                let line = try #require(
                    lines.firstIndex(of: "    id: \(field.id)"),
                    "\(form.rawValue) has no field \(field.id)")
                #expect(lines[line - 1] == "  - type: input", "\(form.rawValue)'s \(field.id) isn't a text field")
            }
        }
    }

    @Test
    func `macOS's version leaves out a zero patch, and its build follows when macOS gives one`() {
        let version = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
        let patched = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 1)
        #expect(FeedbackLink.About.macOS(version, build: "25B78") == "26.1 (25B78)")
        #expect(FeedbackLink.About.macOS(patched, build: nil) == "26.0.1")
        #expect(FeedbackLink.About.build(fromVersionText: "Version 26.1 (Build 25B78)") == "25B78")
        #expect(FeedbackLink.About.build(fromVersionText: "Version 26.1") == nil)
        #expect(FeedbackLink.About.build(fromVersionText: "Version 26.1 (Build )") == nil)
    }

    @Test
    func `this app on this Mac: the version as the About window writes it, and the architecture it runs as`() {
        let current = FeedbackLink.About.current
        let system = ProcessInfo.processInfo.operatingSystemVersion
        #expect(current.version == "\(ProductInfo.version) (\(ProductInfo.build))")
        #expect(current.macOS.hasPrefix("\(system.majorVersion).\(system.minorVersion)"))
        #expect(["arm64", "x86_64"].contains(current.architecture))
    }
}
