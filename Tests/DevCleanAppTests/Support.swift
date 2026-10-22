import AppKit
import DevCleanKit
import Foundation
import SwiftUI
@testable import DevCleanApp

/// A temp folder standing in for HOME, removed when the test lets go of it.
final class TemporaryHome: @unchecked Sendable {
    let root: String
    let path: String

    init() {
        let base = FileManager.default.temporaryDirectory.path(percentEncoded: false)
        root = (base.hasSuffix("/") ? base : base + "/") + "devclean-app-tests-\(UUID().uuidString)"
        path = "\(root)/home"
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    deinit {
        precondition(root.contains("/devclean-app-tests-"), "refusing to remove \(root)")
        try? FileManager.default.removeItem(atPath: root)
    }
}

/// A model on an empty fake home, never scanned, holding the given extras.
@MainActor
func makeModel(home: TemporaryHome, extras: Extras? = nil) -> AppModel {
    let model = AppModel(environment: ["HOME": home.path, "PATH": "/usr/bin:/bin", "DEVCLEAN_PROJECT_DIRS": ""])
    model.extras = extras
    return model
}

/// The smallest size a view accepts: what AppKit asks the window's columns
/// for when it decides how wide and tall they must be.
@MainActor
func minimumSize(of view: some View, model: AppModel) -> CGSize {
    NSHostingController(rootView: view.environment(model)).sizeThatFits(in: .zero)
}

/// Extras like the ones on a machine with Xcode 27.2, a renamed older Xcode
/// with a long name, and runtimes in every state.
let sampleExtras = Extras(
    xcodes: [
        InstalledXcode(path: "/Applications/Xcode.app", version: "27.2", build: "27B48", kilobytes: 12_582_912,
                       lastOpened: Date(timeIntervalSince1970: 1_792_000_000), isSelected: true),
        InstalledXcode(path: "/Applications/Xcode-26.4.1-Release-Candidate-For-Testing.app", version: "26.4.1", build: "17E5170d",
                       kilobytes: 11_534_336, lastOpened: nil, isSelected: false),
    ],
    runtimes: [
        SimulatorRuntime(id: "3AE7A17A-16F5-4C66-93F3-64D01113741A", identifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
                         platform: "iOS", version: "27.1", build: "24A94401", kilobytes: 7_689_179, lastUsedDay: "2026-10-21",
                         daysSinceUsed: 0, simulatorCount: 4),
        SimulatorRuntime(id: "A058C5C7-2E8A-4B00-9AF5-F0959DFA9C92", identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-5",
                         platform: "iOS", version: "18.5", build: "22F77", kilobytes: 8_295_197, lastUsedDay: "2026-03-01",
                         daysSinceUsed: 235, simulatorCount: 0),
        SimulatorRuntime(id: "9E8D7C6B-0000-4000-8000-000000000003", identifier: "com.apple.CoreSimulator.SimRuntime.watchOS-26-1",
                         platform: "watchOS", version: "26.1", build: "23R61", kilobytes: 4_089_446, lastUsedDay: nil,
                         daysSinceUsed: nil, simulatorCount: 1),
    ]
)

/// Results with every item measured, long labels and a full DerivedData breakdown.
let sampleResults: [ItemResult] = Item.allCases.enumerated().map { index, item in
    let breakdown = item == .derivedData ? DerivedDataBreakdown(
        compilationCacheKilobytes: 43_000_000, moduleCacheKilobytes: 4_300_000, otherKilobytes: 6_000_000,
        projects: (1...8).map { n in
            DerivedDataProject(name: "AVeryLongFolderName-\(n)/AnEvenLongerProjectName", status: n == 3 ? .gone : .built("2026-10-2\(n % 10)"),
                               kilobytes: Int64(47_000_000 / n), folder: "/dd/P\(n)", workspacePath: "/w/P\(n)")
        }
    ) : nil
    return ItemResult(
        item: item,
        paths: (0..<(index + 1)).map { "/Users/someone/Library/Somewhere/Deep/Inside/A/Long/Path/\(item.rawValue)-\($0)" },
        kilobytes: Int64(200_000_000 / (index + 1)),
        location: "~/Library/Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Caches/\(item.rawValue)",
        derivedData: breakdown
    )
}
