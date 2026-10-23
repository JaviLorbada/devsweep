import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

/// A model on a temp home with none of the tools, so nothing outside the
/// temp folder runs; its last scan is kept in the temp home's own file.
@MainActor
func scanningModel(home: TemporaryHome, notifier: NotificationPoster = SilentNotificationPoster()) -> AppModel {
    AppModel(
        environment: ["HOME": home.path, "DEVSWEEP_PROJECT_DIRS": ""],
        preferences: Preferences(storage: InMemoryPreferencesStore()),
        notifier: notifier,
        dependencies: Dependencies(tools: .unavailable))
}

@MainActor
func finishScan(_ model: AppModel) async {
    model.scan()
    for _ in 0..<200 where model.isScanning || model.isLoadingExtras {
        try? await Task.sleep(for: .milliseconds(50))
    }
}

func write(_ kilobytes: Int, to folder: String) {
    must { try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true) }
    FileManager.default.createFile(atPath: "\(folder)/blob", contents: Data(count: kilobytes * 1024))
}

@MainActor
@Suite("Remembering the last scan")
struct ScanMemoryTests {
    @Test
    func `A finished scan is shown, dimmed, on the next launch until a new one replaces it`() async {
        let home = TemporaryHome()
        write(64, to: "\(home.path)/Library/Caches/org.swift.swiftpm")
        write(32, to: "\(home.path)/.npm/_cacache")

        let first = scanningModel(home: home)
        await finishScan(first)
        let total = first.reclaimableKilobytes
        #expect(total >= 96)
        #expect(FileManager.default
            .fileExists(atPath: "\(home.path)/Library/Application Support/DevSweep/last-scan.json"))

        let next = scanningModel(home: home)
        #expect(next.statusLine.hasPrefix("Last scanned"))
        #expect(next.showsPrevious)
        #expect(next.reclaimableKilobytes == total)
        #expect(next.rows[.swiftpmCache]?.showsPrevious == true)
        #expect(next.rows[.swiftpmCache]?.shownKilobytes == first.rows[.swiftpmCache]?.kilobytes)
        #expect(next.liveRows.isEmpty, "nothing from the last scan can be cleaned")

        await finishScan(next)
        #expect(!next.showsPrevious)
        #expect(next.rows[.swiftpmCache]?.state == .measured)
        #expect(next.statusLine.hasPrefix("Scanned just now"))
    }

    @Test
    func `A scan of another home is not shown`() async throws {
        let home = TemporaryHome(), other = TemporaryHome()
        write(16, to: "\(other.path)/.npm/_cacache")
        let otherModel = scanningModel(home: other)
        await finishScan(otherModel)
        let saved = "\(other.path)/Library/Application Support/DevSweep/last-scan.json"
        let copy = "\(home.path)/Library/Application Support/DevSweep/last-scan.json"
        try FileManager.default.createDirectory(
            atPath: (copy as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: saved, toPath: copy)

        let model = scanningModel(home: home)
        #expect(!model.showsPrevious)
        #expect(model.statusLine == "Not scanned yet")
    }

    @Test
    func `while measuring, an item counts toward the totals`() {
        var row = AppModel.Row(item: .derivedData)
        row.state = .measuring
        row.progressBytes = 5 * 1024 * 1024
        #expect(row.isCounting)
        #expect(row.shownKilobytes == 5 * 1024)
        row.previous = ItemResult(item: .derivedData, paths: ["/dd"], kilobytes: 900, location: "")
        #expect(row.shownKilobytes == 5 * 1024, "the running count, not the last scan, once it is measuring")
        row.state = .waiting
        #expect(row.showsPrevious)
        #expect(row.shownKilobytes == 900)
    }
}
