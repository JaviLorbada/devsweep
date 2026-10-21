import CoreGraphics

/// Squarified treemap layout (Bruls, Huizing and van Wijk): rows of cells
/// laid along the shorter side, each row grown while it makes the cells
/// closer to square.
public enum Treemap {
    public struct Cell<ID: Hashable>: Equatable {
        public var id: ID
        public var frame: CGRect
    }

    /// Lays out `weights` in a `size` rectangle, in the order given (largest
    /// first gives the best result). Weights of zero or less get no cell.
    public static func squarify<ID: Hashable>(_ weights: [(id: ID, weight: Double)], in size: CGSize) -> [Cell<ID>] {
        let positive = weights.filter { $0.weight > 0 }
        let total = positive.reduce(0) { $0 + $1.weight }
        guard total > 0, size.width > 0, size.height > 0 else { return [] }

        let scale = Double(size.width * size.height) / total
        var remaining = positive.map { (id: $0.id, area: $0.weight * scale) }[...]
        var free = CGRect(origin: .zero, size: size)
        var row: [(id: ID, area: Double)] = []
        var cells: [Cell<ID>] = []

        func worst(_ row: [(id: ID, area: Double)], side: Double) -> Double {
            let sum = row.reduce(0) { $0 + $1.area }
            return row.reduce(0) { result, cell in
                max(result, max(side * side * cell.area / (sum * sum), sum * sum / (side * side * cell.area)))
            }
        }

        func place(_ row: [(id: ID, area: Double)]) {
            let sum = row.reduce(0) { $0 + $1.area }
            if free.width >= free.height {
                let width = sum / max(Double(free.height), 1)
                var y = Double(free.minY)
                for cell in row {
                    let height = cell.area / max(width, 0.001)
                    cells.append(Cell(id: cell.id, frame: CGRect(x: Double(free.minX), y: y, width: width, height: height)))
                    y += height
                }
                free = CGRect(x: free.minX + width, y: free.minY, width: max(free.width - width, 0), height: free.height)
            } else {
                let height = sum / max(Double(free.width), 1)
                var x = Double(free.minX)
                for cell in row {
                    let width = cell.area / max(height, 0.001)
                    cells.append(Cell(id: cell.id, frame: CGRect(x: x, y: Double(free.minY), width: width, height: height)))
                    x += width
                }
                free = CGRect(x: free.minX, y: free.minY + height, width: free.width, height: max(free.height - height, 0))
            }
        }

        while let next = remaining.first {
            let side = max(Double(min(free.width, free.height)), 1)
            if row.isEmpty || worst(row, side: side) >= worst(row + [next], side: side) {
                row.append(next)
                remaining = remaining.dropFirst()
            } else {
                place(row)
                row = []
            }
        }
        if !row.isEmpty { place(row) }
        return cells
    }
}
