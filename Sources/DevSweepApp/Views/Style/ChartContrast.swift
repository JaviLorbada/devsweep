import DevSweepKit
import SwiftUI

/// How the overview's charts draw: how strongly they draw what is faded,
/// waiting or cleaned, the gap between the ring's segments and the blocks'
/// edges. The overview makes it once and hands it down, as it does the rows.
struct ChartContrast {
    /// A segment not selected while another one is.
    var dimmed: Double {
        0.42
    }

    /// What the last scan found, until this scan reaches it.
    var lastScan: Double {
        0.25
    }

    /// An item still being measured, counting up.
    var measuring: Double {
        0.6
    }

    /// A block not measured anew yet: counting, or from the last scan.
    var pending: Double {
        0.5
    }

    /// Segments not measured yet: the ring is whole from the start and fills in.
    var placeholder: Color {
        .primary.opacity(0.07)
    }

    /// Segments already cleaned.
    var cleaned: Color {
        .primary.opacity(0.12)
    }

    /// The gap between two ring segments, in points.
    var ringGap: CGFloat {
        1.6
    }

    var blockEdgeWidth: CGFloat {
        1
    }

    /// A block's edge: its hue, fainter unless selected.
    func blockEdge(_ item: Item, selected: Bool) -> Color {
        selected ? Palette.color(item) : Palette.color(item).opacity(0.6)
    }
}
