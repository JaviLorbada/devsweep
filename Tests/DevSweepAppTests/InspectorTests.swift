import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Inspector")
struct InspectorTests {
    @Test
    func `DerivedData projects go by the folder they live in`() {
        func project(_ name: String) -> DerivedDataProject {
            DerivedDataProject(
                name: name,
                status: .built("2026-10-20"),
                kilobytes: 1,
                folder: "\(name)-abcdefghijklmnop",
                workspacePath: "/Users/someone/Developer/\(name).xcworkspace")
        }
        #expect(DerivedDataParts.displayName(project("atlas-2/Atlas")) == "atlas-2")
        #expect(DerivedDataParts.displayName(project("Atlas-iOS/Atlas")) == "Atlas-iOS")
        #expect(DerivedDataParts.displayName(project("Atlas/Atlas")) == "Atlas")
        #expect(DerivedDataParts.displayName(project("/Loose")) == "Loose")
    }
}
