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
}
