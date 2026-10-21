import CoreGraphics
import Testing
@testable import DevCleanKit

@Suite("Treemap")
struct TreemapTests {
    let size = CGSize(width: 504, height: 244)

    @Test("Cells fill the rectangle exactly, in proportion to their weights")
    func fills() {
        let weights: [(id: String, weight: Double)] = [("a", 25_395), ("b", 6246), ("c", 4710), ("d", 3277), ("e", 2970),
                                                      ("f", 2355), ("g", 1843), ("h", 1434), ("i", 1126), ("j", 922), ("k", 614)]
        let cells = Treemap.squarify(weights, in: size)
        let total = weights.reduce(0) { $0 + $1.weight }
        #expect(cells.map(\.id) == weights.map(\.id))
        let area = cells.reduce(0.0) { $0 + Double($1.frame.width * $1.frame.height) }
        #expect(abs(area - Double(size.width * size.height)) < 1)
        for (cell, weight) in zip(cells, weights) {
            let share = Double(cell.frame.width * cell.frame.height) / Double(size.width * size.height)
            #expect(abs(share - weight.weight / total) < 0.001)
            #expect(cell.frame.minX >= -0.001 && cell.frame.maxX <= size.width + 0.001)
            #expect(cell.frame.minY >= -0.001 && cell.frame.maxY <= size.height + 0.001)
        }
        for (index, cell) in cells.enumerated() {
            for other in cells[(index + 1)...] {
                #expect(cell.frame.intersection(other.frame).width < 0.01 || cell.frame.intersection(other.frame).height < 0.01)
            }
        }
    }

    @Test("Squarified cells stay close to square")
    func aspect() {
        let cells = Treemap.squarify((1...8).map { (id: $0, weight: 1.0) }, in: CGSize(width: 400, height: 200))
        for cell in cells {
            let ratio = max(cell.frame.width / cell.frame.height, cell.frame.height / cell.frame.width)
            #expect(ratio < 2.1)
        }
    }

    @Test("Nothing to lay out gives no cells")
    func empty() {
        #expect(Treemap.squarify([(id: "a", weight: 0.0)], in: size).isEmpty)
        #expect(Treemap.squarify([(id: "a", weight: 1.0)], in: .zero).isEmpty)
        #expect(Treemap.squarify([(id: "a", weight: 3.0), (id: "b", weight: -1)], in: size).map(\.id) == ["a"])
        #expect(Treemap.squarify([(id: "a", weight: 3.0)], in: size).first?.frame == CGRect(origin: .zero, size: size))
    }
}
