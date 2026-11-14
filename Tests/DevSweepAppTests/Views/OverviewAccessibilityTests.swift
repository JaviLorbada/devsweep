import DevSweepKit
import SwiftUI
import Testing
@testable import DevSweepApp

/// What VoiceOver finds on the overview: one element for each segment,
/// block, row and line, saying what `SpokenText` says, in reading order.
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

    @Test
    func `the ring is one element summing it up, holding each family and then its items`() throws {
        let home = TemporaryHome()
        let (app, tree) = self.overview(.ring, home: home)
        let tally = app.scan.tally
        let ring = try #require(tree.first(SpokenText.summary(tally, isScanning: false)))
        let expected = Family.allCases.flatMap { family in
            [SpokenText.family(family, in: tally)]
                + family.items.compactMap { app.scan.rows[$0] }.map { SpokenText.item($0, in: tally) }
        }
        #expect(ring.children.map { SpokenText(label: $0.label, value: $0.value) } == expected)
        #expect(ring.children.filter(\.isSelected).map(\.label) == [Item.derivedData.name])
        #expect(ring.children.allSatisfy { $0.role == "AXButton" && $0.children.isEmpty })

        ring.children.first { $0.label == Item.npmCache.name }?.press()
        #expect(app.overview.selection == .npmCache)
    }

    @Test
    func `the legend's families say their size and share, after the ring`() {
        let home = TemporaryHome()
        let (app, tree) = self.overview(.ring, home: home)
        let tally = app.scan.tally
        let families = Family.allCases.map { SpokenText.family($0, in: tally) }
        let buttons = tree.all.filter { $0.role == "AXButton" && families.map(\.label).contains($0.label) }
        // The ring's own family segments, then the legend's.
        #expect(buttons.map { SpokenText(label: $0.label, value: $0.value) } == families + families)
    }

    @Test
    func `the blocks are one element summing them up, holding each item largest first`() throws {
        let home = TemporaryHome()
        let (app, tree) = self.overview(.blocks, home: home)
        let tally = app.scan.tally
        let blocks = try #require(tree.first(SpokenText.summary(tally, isScanning: false)))
        #expect(blocks.children.map { SpokenText(label: $0.label, value: $0.value) }
            == tally.live.map { SpokenText.item($0, in: tally) })
        #expect(blocks.children.filter(\.isSelected).map(\.label) == [Item.derivedData.name])

        // The total and the families come first, each one element.
        let families = Family.allCases.map { SpokenText.family($0, in: tally) }
        let before = tree.all.prefix { $0.label != blocks.label }.filter(\.children.isEmpty)
        #expect(before.map(\.label) == ["\(SizeText.of(kilobytes: tally.reclaimableKilobytes)), reclaimable"]
            + families.map(\.label))
        #expect(before.dropFirst().map(\.value) == families.map(\.value))
    }

    @Test
    func `each row is one element saying its item and whether it is marked, and pressing it marks it`() throws {
        let home = TemporaryHome()
        let (app, tree) = self.overview(.ring, home: home)
        let tally = app.scan.tally
        let names = Set(Item.allCases.map(\.name))
        let rows = tree.all.filter { names.contains($0.label) && $0.actions.contains("Select") }
        #expect(rows.map { SpokenText(label: $0.label, value: $0.value) }
            == tally.ordered.map { SpokenText.row($0, marked: false, in: tally) })
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
    func `nothing on the overview is an element with nothing to say`() {
        let home = TemporaryHome()
        for chart in WindowViewModel.ChartStyle.allCases {
            let (_, tree) = self.overview(chart, home: home)
            let silent = tree.all.filter { $0.children.isEmpty && $0.label.isEmpty && $0.value.isEmpty }
            #expect(silent.isEmpty, "\(chart.rawValue): \(silent.map(\.role))")
        }
    }

    @Test
    func `the inspector reads its size with its state, then each part of the item in order`() throws {
        let home = TemporaryHome()
        let app = makeApp(home: home)
        app.showResults(sampleResults)
        let tree = AccessibilityTree(ItemInspector().environment(models: app), width: 320, height: 1400)
        let result = try #require(app.scan.rows[.derivedData]?.result)
        let hero = "\(SizeText.of(kilobytes: result.kilobytes)), reclaimable"
        #expect(tree.all.contains { $0.label == hero })

        // Largest first, the five largest projects among the shared parts,
        // then the line that sums the other three.
        let projects = try #require(result.derivedData?.projects)
        func project(_ index: Int) -> SpokenText {
            let project = projects[index]
            let status = switch project.status {
            case let .built(day): "built \(day)"
            case .gone: "project gone"
            }
            return .line(
                "AVeryLongFolderName-\(index + 1)",
                kilobytes: project.kilobytes,
                status: status,
                marked: false)
        }
        let spoken: [SpokenText] = [
            project(0),
            .line("Shared compilation cache", kilobytes: 43_000_000, status: "", marked: false),
            project(1), project(2), project(3), project(4),
            .line("Other", kilobytes: 6_000_000, status: "", marked: false),
            .line("Shared module cache", kilobytes: 4_300_000, status: "", marked: false),
            .line(
                "3 more projects",
                kilobytes: projects[5...].reduce(0) { $0 + $1.kilobytes },
                status: "",
                marked: nil),
        ]
        let shown = tree.all.filter { element in spoken.contains { $0.label == element.label } }
        #expect(shown.map { SpokenText(label: $0.label, value: $0.value) } == spoken)
        let insideLines = shown.flatMap(\.children)
        #expect(insideLines.isEmpty)

        try #require(shown.first { $0.label == "Shared compilation cache" }).press()
        #expect(app.marks.markedParts(of: .derivedData) == [.compilationCache])
    }
}
