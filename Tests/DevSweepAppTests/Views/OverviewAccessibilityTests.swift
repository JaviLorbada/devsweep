import DevSweepKit
import SwiftUI
import Testing
@testable import DevSweepApp

/// What VoiceOver finds on the overview: one element for each segment,
/// block, row and line, saying what `SpokenText` says, in reading order,
/// and each thing said once.
@MainActor
@Suite("Overview accessibility")
struct OverviewAccessibilityTests {
    /// The overview's center, measured, with DerivedData selected.
    func overview(_ chart: WindowViewModel.ChartStyle, home: TemporaryHome) -> (AppCoordinator, AccessibilityTree) {
        let app = makeApp(home: home)
        app.showResults(sampleResults)
        app.window.chartStyle = chart
        return (app, AccessibilityTree(OverviewContent().environment(models: app), width: 900, height: 1100))
    }

    func spoken(_ elements: [AccessibilityTree.Element]) -> [SpokenText] {
        elements.map { SpokenText(label: $0.label, value: $0.value) }
    }

    @Test
    func `the ring is one element summing it up, holding each item clockwise`() throws {
        let home = TemporaryHome()
        let (app, tree) = self.overview(.ring, home: home)
        let tally = app.scan.tally
        let ring = try #require(tree.first(SpokenText.summary(tally, isScanning: false)))
        let clockwise = Family.allCases.flatMap { $0.items.compactMap { app.scan.rows[$0] } }
        #expect(self.spoken(ring.children) == clockwise.map { SpokenText.item($0, in: tally) })
        #expect(ring.children.filter(\.isSelected).map(\.label) == [Item.derivedData.name])
        let roles = Set(ring.children.map(\.role))
        let inside = ring.children.flatMap(\.children)
        #expect(roles == ["AXButton"] && inside.isEmpty)

        ring.children.first { $0.label == Item.npmCache.name }?.press()
        #expect(app.overview.selection == .npmCache)
    }

    @Test
    func `the families are read once, from the legend after the ring, with their size and share`() {
        let home = TemporaryHome()
        let (app, tree) = self.overview(.ring, home: home)
        let families = Family.allCases.map { SpokenText.family($0, in: app.scan.tally) }
        let read = tree.all.filter { element in families.contains { $0.label == element.label } }
        #expect(self.spoken(read) == families)
    }

    @Test
    func `the blocks are one element summing them up, holding the families and then each item largest first`() throws {
        let home = TemporaryHome()
        let (app, tree) = self.overview(.blocks, home: home)
        let tally = app.scan.tally
        let summary = SpokenText.summary(tally, isScanning: false)
        let blocks = try #require(tree.first(summary))
        let families = Family.allCases.map { SpokenText.family($0, in: tally) }
        #expect(self.spoken(blocks.children) == families + tally.live.map { SpokenText.item($0, in: tally) })
        #expect(blocks.children.filter(\.isSelected).map(\.label) == [Item.derivedData.name])
        // The summary says the total; nothing says it again.
        let total = SpokenText.total(tally, isScanning: false).label
        #expect(tree.all.filter { $0.label.contains(total) }.map(\.label) == [summary])
    }

    @Test
    func `each row is one element saying its item as shown and if it is marked, and pressing marks it`() throws {
        let home = TemporaryHome()
        let (app, tree) = self.overview(.ring, home: home)
        let tally = app.scan.tally
        let rows = tree.all.filter { $0.actions.contains("Select") }
        #expect(self.spoken(rows) == tally.ordered.map { SpokenText.row($0, marked: false, in: tally) })
        let inside = rows.flatMap(\.children)
        #expect(inside.isEmpty)
        #expect(rows.map(\.actions) == Array(repeating: ["Select", "Clean"], count: rows.count))

        let first = try #require(rows.first)
        first.press()
        #expect(app.marks.marked == [.derivedData])
        rows[1].perform("Select")
        #expect(app.overview.selection == tally.ordered[1].item)
    }

    @Test
    func `a row's Clean action selects the item and asks to clean it`() async throws {
        let home = TemporaryHome()
        let (app, tree) = self.overview(.ring, home: home)
        // Deleting for good always asks first, so nothing is cleaned.
        app.cleaning.moveToTrash = false
        let item = app.scan.tally.ordered[2].item
        let row = try #require(tree.all.first { $0.actions.contains("Clean") && $0.label.hasPrefix(item.name) })
        row.perform("Clean")
        await waitUntil { app.cleaning.pendingClean != nil }
        #expect(app.overview.selection == item)
        #expect(app.cleaning.pendingClean?.items == [item])
    }

    @Test
    func `the items list and the inspector's item are headings`() {
        let home = TemporaryHome()
        let (app, tree) = self.overview(.ring, home: home)
        #expect(tree.all.filter(\.isHeading).map(\.label) == ["Items"])
        let inspector = AccessibilityTree(ItemInspector().environment(models: app), width: 320, height: 1400)
        let title = app.scan.rows[.derivedData]?.result?.label
        #expect(inspector.all.filter(\.isHeading).map(\.label) == [title])
    }

    @Test
    func `nothing on the overview is an element with nothing to say`() {
        let home = TemporaryHome()
        for chart in WindowViewModel.ChartStyle.allCases {
            let (_, tree) = self.overview(chart, home: home)
            let silent = tree.all.filter { $0.children.isEmpty && $0.label.isEmpty && $0.value.isEmpty }
            #expect(silent.isEmpty, "\(chart.rawValue): \(silent.map(\.role))")
        }
    }

    @Test
    func `the inspector reads its headline, then each part of the item in order`() throws {
        let home = TemporaryHome()
        let app = makeApp(home: home)
        app.showResults(sampleResults)
        let tree = AccessibilityTree(ItemInspector().environment(models: app), width: 320, height: 1400)
        let row = try #require(app.scan.rows[.derivedData])
        let headline = SpokenText.headline(row)
        #expect(tree.all.contains { $0.label == headline.sentence })

        // Largest first, the five largest projects among the shared parts,
        // then the line that sums the other three.
        let projects = try #require(row.result?.derivedData?.projects)
        func project(_ index: Int) -> SpokenText {
            let project = projects[index]
            let status = switch project.status {
            case let .built(day): "built \(day)"
            case .gone: "project gone"
            }
            let name = "AVeryLongFolderName-\(index + 1)"
            return .line(name, detail: nil, kilobytes: project.kilobytes, status: status, marked: false)
        }
        let rest = projects[5...].reduce(0) { $0 + $1.kilobytes }
        let spoken: [SpokenText] = [
            project(0),
            .line("Shared compilation cache", detail: nil, kilobytes: 43_000_000, status: "", marked: false),
            project(1), project(2), project(3), project(4),
            .line("Other", detail: nil, kilobytes: 6_000_000, status: "", marked: false),
            .line("Shared module cache", detail: nil, kilobytes: 4_300_000, status: "", marked: false),
            .line("3 more projects", detail: nil, kilobytes: rest, status: "", marked: nil),
        ]
        let shown = tree.all.filter { element in spoken.contains { $0.label == element.label } }
        #expect(self.spoken(shown) == spoken)
        let insideLines = shown.flatMap(\.children)
        #expect(insideLines.isEmpty)

        try #require(shown.first { $0.label == "Shared compilation cache" }).press()
        #expect(app.marks.markedParts(of: .derivedData) == [.compilationCache])
    }
}
