import DevSweepKit
import SwiftUI

/// How strongly the charts draw what is faded, waiting or cleaned, and the
/// edges between segments and blocks. With Increase Contrast every faded
/// tone draws stronger, the ring's segments sit further apart, and blocks
/// take an edge in a deeper shade of their hue, so neighbours stay apart
/// from each other and from the card.
struct ChartTones {
    let increasedContrast: Bool

    init(_ contrast: ColorSchemeContrast) {
        self.increasedContrast = contrast == .increased
    }

    /// A segment not selected while another one is.
    var dimmed: Double {
        self.increasedContrast ? 0.7 : 0.42
    }

    /// What the last scan found, until this scan reaches it.
    var lastScan: Double {
        self.increasedContrast ? 0.45 : 0.25
    }

    /// An item still being measured, counting up.
    var measuring: Double {
        self.increasedContrast ? 0.8 : 0.6
    }

    /// A block not measured anew yet: counting, or from the last scan.
    var pending: Double {
        self.increasedContrast ? 0.75 : 0.5
    }

    /// Segments not measured yet: the ring is whole from the start and fills in.
    var placeholder: Color {
        .primary.opacity(self.increasedContrast ? 0.16 : 0.07)
    }

    /// Segments already cleaned.
    var cleaned: Color {
        .primary.opacity(self.increasedContrast ? 0.24 : 0.12)
    }

    /// The gap between two ring segments, in points.
    var ringGap: CGFloat {
        self.increasedContrast ? 3 : 1.6
    }

    var blockEdgeWidth: CGFloat {
        self.increasedContrast ? 1.5 : 1
    }

    /// A block's edge: its hue, fainter unless selected; with Increase
    /// Contrast a deeper shade of it, selected or not.
    func blockEdge(_ item: Item, selected: Bool) -> Color {
        if self.increasedContrast {
            return Palette.edge(item)
        }
        return selected ? Palette.color(item) : Palette.color(item).opacity(0.6)
    }
}
