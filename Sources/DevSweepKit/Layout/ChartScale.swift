import Foundation

/// The share of a chart each size is drawn with.
///
/// Developer caches span five orders of magnitude: next to 192 GB of
/// DerivedData, 9 MB of Gradle builds would be a sliver no one can see or
/// click. Shares follow the sizes raised to a power below one, which keeps
/// their order but narrows the gaps, and every size above zero gets at
/// least a minimum share. Labels still show the exact sizes.
public enum ChartScale {
    /// The power the sizes are raised to.
    public static let exponent = 0.6
    /// The least share a size above zero is drawn with.
    public static let minimumShare = 0.025

    /// Shares in the order of `sizes`, adding up to 1: a larger size never
    /// gets a smaller share, every size above zero gets at least
    /// `minimumShare`, and zero or less gets nothing. When there are too many
    /// sizes for each to have the minimum, they share equally. All zeros give
    /// all zeros.
    public static func shares(_ sizes: [Double]) -> [Double] {
        var shares = sizes.map { _ in 0.0 }
        let positive = sizes.indices.filter { sizes[$0] > 0 }
        guard !positive.isEmpty else { return shares }
        if Double(positive.count) * self.minimumShare >= 1 {
            for index in positive {
                shares[index] = 1 / Double(positive.count)
            }
            return shares
        }

        let weights = sizes.map { $0 > 0 ? pow($0, self.exponent) : 0 }
        // Sizes whose share would fall below the minimum are raised to it, and
        // the rest share what is left by weight, until none falls below. The
        // largest always stays above, so this ends with something left to share.
        var raised: Set<Int> = []
        while true {
            let free = positive.filter { !raised.contains($0) }
            let room = 1 - Double(raised.count) * self.minimumShare
            let total = free.reduce(0) { $0 + weights[$1] }
            let below = free.filter { weights[$0] / total * room < self.minimumShare }
            guard below.isEmpty else {
                raised.formUnion(below)
                continue
            }
            for index in free {
                shares[index] = weights[index] / total * room
            }
            for index in raised {
                shares[index] = self.minimumShare
            }
            return shares
        }
    }
}
