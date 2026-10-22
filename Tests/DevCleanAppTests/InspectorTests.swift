import DevCleanKit
import Testing
@testable import DevCleanApp

@MainActor
@Suite("Inspector")
struct InspectorTests {
    @Test("DerivedData projects go by the folder they live in")
    func projectNames() {
        func project(_ name: String) -> DerivedDataProject {
            DerivedDataProject(name: name, status: .built("2026-10-20"), kilobytes: 1, folder: "\(name)-abcdefghijklmnop",
                               workspacePath: "/Users/someone/Developer/\(name).xcworkspace")
        }
        #expect(DerivedDataParts.displayName(project("kite-1/Waypoint")) == "kite-1")
        #expect(DerivedDataParts.displayName(project("Waypoint-iOS/Waypoint")) == "Waypoint-iOS")
        #expect(DerivedDataParts.displayName(project("Atlas/Atlas")) == "Atlas")
        #expect(DerivedDataParts.displayName(project("/Loose")) == "Loose")
    }
}
