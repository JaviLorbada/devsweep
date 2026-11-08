import DevSweepKit
import SwiftUI

// What the screens for things DevSweep lists but never deletes on its own
// share: the cards, their columns and an empty row. The screens are in
// RuntimesViews.swift and XcodesViews.swift.

/// A card with a title line and rows. It tells its rows which columns fit,
/// so a narrow window drops columns instead of making the card wider than
/// its column.
struct ExtrasCard<Rows: View>: View {
    let title: String
    let note: String
    /// Rows the card holds, each 41 points with its divider.
    let rowCount: Int
    @ViewBuilder let rows: Rows

    /// Sized from the width it is given (its height is fixed by its rows), so
    /// its minimum never follows the width it last had.
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(self.title).fontWeight(.semibold).lineLimit(1).layoutPriority(1)
                    Text(self.note).font(.callout).foregroundStyle(.muted).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
                self.rows
            }
            .environment(\.extrasColumns, ExtrasColumns(width: proxy.size.width))
        }
        .frame(height: 34 + CGFloat(max(self.rowCount, 1)) * 41)
        .card()
    }
}

/// Which columns an extras row shows. The bar goes first, then the date.
enum ExtrasColumns {
    case full
    case withoutBar
    case compact

    init(width: CGFloat) {
        self = width >= 700 ? .full : width >= 560 ? .withoutBar : .compact
    }

    var showsBar: Bool {
        self == .full
    }

    var showsDate: Bool {
        self != .compact
    }
}

extension EnvironmentValues {
    @Entry var extrasColumns = ExtrasColumns.compact
}

struct EmptyExtrasRow: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.6)
            Text(self.text)
                .foregroundStyle(.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 40)
        }
    }
}
