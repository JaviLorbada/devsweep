import CoreGraphics
import Testing
@testable import DevSweepKit

@Suite("Chart scale")
struct ChartScaleTests {
    static let gigabyte = 1_048_576.0
    static let megabyte = 1024.0
    /// A real home's items, in kilobytes, largest first.
    static let realHome = [
        192 * gigabyte, 175 * gigabyte, 2.6 * gigabyte, 1.5 * gigabyte, 778 * megabyte, 419 * megabyte,
        387 * megabyte, 104 * megabyte, 84 * megabyte, 21 * megabyte, 9 * megabyte,
    ]

    @Test
    func `shares add up to one`() {
        for sizes in [Self.realHome, [1.0], [5, 5], [3, 0, 1], [10, 1e-3, 1e6]] {
            #expect(abs(ChartScale.shares(sizes).reduce(0, +) - 1) < 1e-9, "\(sizes)")
        }
    }

    @Test
    func `a larger size never gets a smaller share, and shares stay in the order given`() {
        let sizes = [21 * Self.megabyte, 192 * Self.gigabyte, 9 * Self.megabyte, 2.6 * Self.gigabyte]
        let shares = ChartScale.shares(sizes)
        #expect(shares.count == sizes.count)
        for i in sizes.indices {
            for j in sizes.indices where sizes[i] > sizes[j] {
                #expect(shares[i] >= shares[j])
            }
        }
        #expect(shares[1] == shares.max())
    }

    @Test
    func `every size above zero gets at least the minimum`() {
        let shares = ChartScale.shares(Self.realHome)
        #expect(shares.allSatisfy { $0 >= ChartScale.minimumShare - 1e-12 })
        #expect(abs(shares[10] - ChartScale.minimumShare) < 1e-12)
        // Sizes close together keep their proportions, softened.
        let close = ChartScale.shares([4, 1])
        #expect(abs(close[0] / close[1] - pow(4, ChartScale.exponent)) < 1e-9)
    }

    @Test
    func `zeros get nothing and take no part`() {
        #expect(ChartScale.shares([]).isEmpty)
        #expect(ChartScale.shares([0, 0]) == [0, 0])
        #expect(ChartScale.shares([0, 7, -1]) == [0, 1, 0])
        let withZeros = ChartScale.shares([8, 0, 1])
        let without = ChartScale.shares([8, 1])
        #expect(withZeros[1] == 0)
        #expect(abs(withZeros[0] - without[0]) < 1e-12 && abs(withZeros[2] - without[1]) < 1e-12)
    }

    @Test
    func `too many sizes for the minimum share equally`() {
        let count = Int((1 / ChartScale.minimumShare).rounded())
        let sizes = (1...count).map { Double($0 * $0) } + [0]
        let shares = ChartScale.shares(sizes)
        #expect(shares.dropLast().allSatisfy { abs($0 - 1 / Double(count)) < 1e-12 })
        #expect(shares.last == 0)
    }

    @Test
    func `every block on a real home is at least 20 points across`() {
        // The blocks chart's size in the narrowest center column and with the window 1280 wide.
        for size in [CGSize(width: 206, height: 248), CGSize(width: 462, height: 248)] {
            let shares = ChartScale.shares(Self.realHome)
            let cells = Treemap.squarify(shares.enumerated().map { (id: $0.offset, weight: $0.element) }, in: size)
            #expect(cells.count == Self.realHome.count)
            for cell in cells {
                #expect(min(cell.frame.width, cell.frame.height) >= 20, "\(size): \(cell.frame)")
            }
        }
    }
}
