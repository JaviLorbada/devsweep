import Foundation
import Testing
@testable import DevCleanKit

@Suite("Report format")
struct ReportFormatTests {
    @Test("Sizes use binary multiples with decimal labels", arguments: [
        (Int64(0), "0 KB"),
        (1023, "1023 KB"),
        (1024, "1 MB"),
        (1_048_575, "1023 MB"),
        (1_048_576, "1.0 GB"),
        (1_101_005, "1.1 GB"),
        (1_572_864, "1.5 GB"),
        (8_388_608, "8.0 GB"),
        (1_073_741_824, "1024.0 GB"),
    ])
    func human(kilobytes: Int64, expected: String) {
        #expect(Report.human(kilobytes: kilobytes) == expected)
    }

    @Test("An item row pads by bytes, like printf under LC_ALL=C")
    func row() {
        let result = ItemResult(item: .swiftpmBuilds, paths: ["/a", "/b"], kilobytes: 8, location: ".build next to a Package.swift, in project folders")
        #expect(Report.row(result) == """
              swiftpm-builds   SwiftPM .build folders (2)                   8 KB
                               .build next to a Package.swift, in project folders

            """)
    }

    @Test("An empty item shows none and no count")
    func emptyRow() {
        let result = ItemResult(item: .toolCaches, paths: [], kilobytes: 0, location: "where")
        #expect(Report.row(result, style: .terminal) == """
              tool-caches      Tool caches                                  none
                               \u{1B}[2mwhere\u{1B}[0m

            """)
    }

    @Test("The DerivedData breakdown matches the script's columns")
    func derivedData() {
        let projects = (1...7).map { n in
            DerivedDataProject(name: "P\(n)/P\(n)", status: .built("2026-09-0\(n)"), kilobytes: Int64(80 - n), folder: "/dd/P\(n)", workspacePath: "/w")
        } + [DerivedDataProject(name: "AVeryLongProjectFolderName/App", status: .gone, kilobytes: 1, folder: "/dd/L", workspacePath: "/w")]
        let breakdown = DerivedDataBreakdown(compilationCacheKilobytes: 2048, moduleCacheKilobytes: 4, otherKilobytes: 4, projects: projects)
        let result = ItemResult(item: .derivedData, paths: ["/dd"], kilobytes: breakdown.totalKilobytes, location: "~/Library/Developer/Xcode/DerivedData", derivedData: breakdown)
        #expect(Report.row(result) == """
              derived-data     Xcode DerivedData                            2 MB
                               ~/Library/Developer/Xcode/DerivedData
                                 Compilation cache, all projects            2 MB
                                 Module cache, all projects                 4 KB
                                 P1/P1                 built 2026-09-01    79 KB
                                 P2/P2                 built 2026-09-02    78 KB
                                 P3/P3                 built 2026-09-03    77 KB
                                 P4/P4                 built 2026-09-04    76 KB
                                 P5/P5                 built 2026-09-05    75 KB
                                 3 more projects                          148 KB
                                 Other                                      4 KB
                               Each part comes back as you build; projects you no longer build stay gone.

            """)
    }

    @Test("Six projects end with one more project")
    func sixProjects() {
        let projects = (1...6).map {
            DerivedDataProject(name: "P\($0)/P\($0)", status: .gone, kilobytes: 8, folder: "/\($0)", workspacePath: "/w")
        }
        let text = Report.derivedData(DerivedDataBreakdown(projects: projects))
        #expect(text.contains("1 more project                             8 KB\n"))
        #expect(!text.contains("Compilation cache"))
        #expect(!text.contains("Other"))
    }

    @Test("Long project names are cut to 21 bytes")
    func longNames() {
        let project = DerivedDataProject(name: "AVeryLongProjectFolderName/AnEvenLongerProjectName", status: .gone, kilobytes: 8, folder: "/", workspacePath: "/w")
        #expect(Report.derivedData(DerivedDataBreakdown(projects: [project])).hasPrefix(
            "                     AVeryLongProjectFolde project gone         8 KB\n"
        ))
    }

    @Test("The summary prints Total and Free space now")
    func summary() {
        #expect(Report.summary(totalKilobytes: nil, freeKilobytes: 30_000_000) == """
              ------------------------------------------------------------------
              Total                                                         none
              Free space now                                             28.6 GB


            """)
        #expect(Report.summary(totalKilobytes: 3_077_864, freeKilobytes: 1).contains("Total                                                       2.9 GB\n"))
    }

    @Test("Project folder lines", arguments: [
        (ProjectFolders(found: ["~/Workspace"]), "Project folders: ~/Workspace\n\n"),
        (ProjectFolders(found: ["~/A", "~/B"], missing: ["~/C"]), "Project folders: ~/A, ~/B (not found: ~/C)\n\n"),
        (ProjectFolders(found: ["~/A"], outside: ["~/Code"]), "Project folders: ~/A (outside your home folder, skipped: ~/Code)\n\n"),
        (ProjectFolders(found: ["~/A"], missing: ["~/M"], outside: ["~/O"]), "Project folders: ~/A (not found: ~/M; outside your home folder, skipped: ~/O)\n\n"),
        (ProjectFolders(), "Project folders: none found.\nUse --projects or DEVCLEAN_PROJECT_DIRS to say where your code lives.\n\n"),
        (ProjectFolders(missing: ["~/Nope"]), "Project folders: none found (looked for ~/Nope).\nUse --projects or DEVCLEAN_PROJECT_DIRS to say where your code lives.\n\n"),
        (ProjectFolders(outside: ["~/Code"]), "Project folders: none found (outside your home folder, skipped: ~/Code).\nUse --projects or DEVCLEAN_PROJECT_DIRS to say where your code lives.\n\n"),
    ])
    func projectFolders(folders: ProjectFolders, expected: String) {
        #expect(Report.projectFolders(folders) == expected)
    }

    @Test("The extras section lists Xcodes and runtimes with their notes")
    func extras() throws {
        let home = FakeHome()
        let policy = try PathPolicy(home: home.home)
        let extras = Extras(
            xcodes: [
                InstalledXcode(path: home.path("Applications/Xcode.app"), version: "27.0", build: "27A266a", kilobytes: 8, lastOpened: Date(timeIntervalSince1970: 1_790_000_000), isSelected: true),
                InstalledXcode(path: "/Applications/Xcode-beta.app", version: "?", build: "?", kilobytes: 12_000_000, lastOpened: nil, isSelected: false),
            ],
            runtimes: [
                SimulatorRuntime(id: "A", identifier: "i", platform: "iOS", version: "27.0", build: "24A434", kilobytes: 8_388_608, lastUsedDay: "2026-10-21", daysSinceUsed: 0, simulatorCount: 1),
                SimulatorRuntime(id: "B", identifier: "j", platform: "iOS", version: "17.5", build: "21F79", kilobytes: 7_340_032, lastUsedDay: "2020-01-01", daysSinceUsed: 2485, simulatorCount: 3),
                SimulatorRuntime(id: "C", identifier: "k", platform: "watchOS", version: "18.0", build: "22A3351", kilobytes: 977, lastUsedDay: nil, daysSinceUsed: nil, simulatorCount: 0),
            ]
        )
        #expect(Report.extras(extras, staleDays: 90, policy: policy) == """
            Also worth a look. devclean never deletes these:

            Xcode versions
              Xcode 27.0 (27A266a)           8 KB   opened 2026-09-21, selected
                ~/Applications/Xcode.app
              Xcode ? (?)                 11.4 GB   last opened unknown
                /Applications/Xcode-beta.app
              Each Xcode keeps its own compilation cache in DerivedData. To remove
              one you no longer need, quit it and move it to the Trash.

            Simulator runtimes
              iOS 27.0 (24A434)            8.0 GB   used 2026-10-21, 1 simulator
              iOS 17.5 (21F79)             7.0 GB   used 2020-01-01, 3 simulators
                Not used in 2485 days. Remove with: xcrun simctl runtime delete B
              watchOS 18.0 (22A3351)       977 KB   never used, 0 simulators
                No simulators. Remove with: xcrun simctl runtime delete C


            """)
    }

    @Test("Empty extras say None found")
    func emptyExtras() throws {
        let home = FakeHome()
        let text = Report.extras(Extras(), staleDays: 90, policy: try PathPolicy(home: home.home))
        #expect(text == "Also worth a look. devclean never deletes these:\n\nXcode versions\n  None found.\n\nSimulator runtimes\n  None found.\n\n")
    }
}
