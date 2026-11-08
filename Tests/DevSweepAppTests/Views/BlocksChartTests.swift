import CoreGraphics
import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Blocks")
struct BlocksChartTests {
    @Test
    func `a cell too thin for the gap is left out rather than drawn out of place`() {
        // 183 GB next to 9 MB: the small cell is a sliver under 3 points.
        let cells = Treemap.squarify(
            [(id: "derived-data", weight: 183_000_000.0), (id: "gradle-builds", weight: 9000)],
            in: CGSize(width: 504, height: 244))
        #expect(cells.contains { $0.id == "gradle-builds" && min($0.frame.width, $0.frame.height) < 3 })
        let drawn = BlocksChart.drawnCells(cells)
        #expect(drawn.map(\.id) == ["derived-data"])
    }

    @Test
    func `drawn cells are inset by the gap and stay inside the chart`() {
        let size = CGSize(width: 504, height: 244)
        let cells = Treemap.squarify([(id: "a", weight: 3.0), (id: "b", weight: 2), (id: "c", weight: 1)], in: size)
        let drawn = BlocksChart.drawnCells(cells)
        #expect(drawn.map(\.id) == ["a", "b", "c"])
        for (cell, original) in zip(drawn, cells) {
            #expect(cell.frame == original.frame.insetBy(dx: BlocksChart.cellInset, dy: BlocksChart.cellInset))
            #expect(CGRect(origin: .zero, size: size).contains(cell.frame))
        }
    }

    @Test
    func `a block is labeled when the start of its name and its size fit, in points`() {
        // Tool caches and Xcode build folders got these cells at 1280 wide,
        // and the old fixed 78 by 36 points left them blank.
        #expect(BlocksChart.label(for: CGSize(width: 67, height: 92), name: "Tool caches", sizeText: "9 MB")
            == .nameAndSize)
        #expect(BlocksChart.label(for: CGSize(width: 73, height: 72), name: "Xcode build folders", sizeText: "7 MB")
            == .nameAndSize)
        // Too narrow for four letters.
        #expect(BlocksChart.label(for: CGSize(width: 30, height: 92), name: "Tool caches", sizeText: "9 MB") == nil)
        // What it needs follows the text: a short name and size fit where a long size doesn't.
        #expect(BlocksChart.label(for: CGSize(width: 52, height: 60), name: "npm", sizeText: "9 MB") == .nameAndSize)
        #expect(BlocksChart.label(for: CGSize(width: 52, height: 60), name: "npm", sizeText: "1023 MB") == nil)
    }

    @Test
    func `a block too low for two lines shows its name alone, when the name fits`() {
        // The flat Gradle block in round 6's drawing, about 120 by 31 points, was blank.
        #expect(BlocksChart.label(for: CGSize(width: 120, height: 31), name: "Gradle build folders", sizeText: "4 MB")
            == .name)
        #expect(BlocksChart.label(for: CGSize(width: 400, height: 30), name: "Tool caches", sizeText: "9 MB") == .name)
        // The size doesn't need to fit, only the name.
        #expect(BlocksChart.label(for: CGSize(width: 52, height: 30), name: "npm", sizeText: "1023 MB") == .name)
        // Too low even for one line, or too narrow for the name.
        #expect(BlocksChart.label(for: CGSize(width: 120, height: 26), name: "Tool caches", sizeText: "9 MB") == nil)
        #expect(BlocksChart.label(for: CGSize(width: 30, height: 30), name: "Tool caches", sizeText: "9 MB") == nil)
    }
}
