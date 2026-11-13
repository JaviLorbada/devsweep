import DevSweepKit

/// The ring of the five families that the app icon shows and the menu bar
/// glyph draws: each family's share, clockwise from the top, and the gaps
/// between them. The icon itself is artwork, in docs/icon.
enum IconRing {
    /// Each family's share of the ring, clockwise from the top.
    static let shares: [(family: Family, share: Double)] = [
        (.xcode, 0.40), (.swiftPackages, 0.20), (.homebrew, 0.16), (.npm, 0.13), (.otherTools, 0.11),
    ]
    /// The gap between two segments, as a share of the ring.
    static let gap = 0.014

    /// Where each segment starts and ends around the ring, gaps taken out.
    static var segments: [(family: Family, from: Double, to: Double)] {
        self.segments(gap: self.gap)
    }

    /// The segments with gaps of another share, for the menu bar's glyph.
    static func segments(gap: Double) -> [(family: Family, from: Double, to: Double)] {
        var start = 0.0
        return self.shares.map { family, share in
            defer { start += share }
            return (family, start + gap / 2, start + share - gap / 2)
        }
    }
}
