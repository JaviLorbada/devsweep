import Foundation
import Testing
@testable import DevSweepKit

@Suite("Build identity")
struct BuildIdentityTests {
    @Test
    func `a development build names its commit, and says when the tree had changes`() {
        let clean = BuildIdentity(info: ["DevSweepCommit": "506cc8c", "DevSweepTreeDirty": false])
        #expect(clean.commitDescription == "506cc8c")
        #expect(clean.statusNote == "Built from 506cc8c.")
        let dirty = BuildIdentity(info: ["DevSweepCommit": "506cc8c", "DevSweepTreeDirty": true])
        #expect(dirty.statusNote == "Built from 506cc8c with uncommitted changes.")
    }

    @Test
    func `a release keeps its status line clean, and an unpackaged run knows nothing`() {
        let release = BuildIdentity(info: ["DevSweepCommit": "506cc8c", "DevSweepReleaseSigned": true])
        #expect(release.commitDescription == "506cc8c")
        #expect(release.statusNote == nil)
        let unpackaged = BuildIdentity(info: [:])
        #expect(unpackaged.commit == nil && unpackaged.commitDescription == nil && unpackaged.statusNote == nil)
    }

    @Test
    func `a development build calls itself DevSweep Dev and keeps its own data`() {
        let development = BuildIdentity(info: ["DevSweepCommit": "506cc8c", "DevSweepDevelopment": true])
        #expect(development.isDevelopment)
        #expect(development.appName == "DevSweep Dev")
        #expect(development.supportFolder == "DevSweep Dev")
        for released in [BuildIdentity(info: ["DevSweepDevelopment": false]), BuildIdentity(info: [:])] {
            #expect(!released.isDevelopment)
            #expect(released.appName == "DevSweep")
            #expect(released.supportFolder == "DevSweep")
        }
    }

    @Test
    func `package_app.sh writes the keys the app reads`() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(contentsOf: root.appending(path: "Scripts/package_app.sh"), encoding: .utf8)
        for key in ["DevSweepCommit", "DevSweepTreeDirty", "DevSweepReleaseSigned", "DevSweepDevelopment"] {
            #expect(script.contains("<key>\(key)</key>"), "\(key)")
        }
    }
}
