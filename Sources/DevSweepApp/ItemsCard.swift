import DevSweepKit
import SwiftUI

/// The eleven items, largest first: mark, color, name, a proportional bar,
/// size and what can be done with it.
struct ItemsCard: View {
    @Environment(AppModel.self) private var model

    /// The bar is the first column to go when the center column narrows.
    static func showsBar(forWidth width: CGFloat) -> Bool { width >= 600 }

    static let headerHeight: CGFloat = 34
    static let rowHeight: CGFloat = 33

    /// Sized from the width it is given (its height is fixed by its rows), so
    /// its minimum never follows the width it last had.
    var body: some View {
        let rows = self.model.orderedRows
        GeometryReader { proxy in
            self.table(rows: rows, showsBar: Self.showsBar(forWidth: proxy.size.width))
        }
        .frame(height: Self.headerHeight + CGFloat(rows.count) * Self.rowHeight)
        .card()
        // The last row's selection follows the card's corners.
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func table(rows: [AppModel.Row], showsBar: Bool) -> some View {
        let largest = Double(max(rows.map(\.shownKilobytes).max() ?? 1, 1))
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Items").fontWeight(.semibold).layoutPriority(1)
                Text(self.note)
                    .font(.callout)
                    .foregroundStyle(.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Mark all") { self.model.markAll() }
                Button("Mark none") { self.model.markNone() }
            }
            .buttonStyle(.link)
            .font(.callout)
            .padding(.horizontal, 14)
            .frame(height: Self.headerHeight)

            ForEach(rows) { row in
                Divider().opacity(0.6)
                ItemRow(row: row, largest: largest, showsBar: showsBar)
            }
        }
    }

    private var note: String {
        let count = self.model.scanOrder.count
        return self.model.isScanning ? "\(self.model.measuredCount) of \(count) measured, largest "
            + "first" : "\(count), largest first"
    }
}

struct ItemRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appearsActive) private var appearsActive
    let row: AppModel.Row
    let largest: Double
    var showsBar = true

    var body: some View {
        let selected = self.model.selection == self.row.item
        // On the selection color, marks turn white like a table's icons, or a
        // dark blue item would vanish on it.
        let emphasized = selected && self.appearsActive
        HStack(spacing: 12) {
            Toggle("Mark \(self.row.item.name) for cleaning", isOn: Binding(
                get: { self.model.marked.contains(self.row.item) && self.row.isLive },
                set: { self.model.setMarked(self.row.item, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!self.row.isLive)

            Dot(color: emphasized ? .white : Palette.color(self.row.item))

            Button {
                self.model.selection = self.row.item
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(self.row.result?.label ?? self.row.item.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(self.row.item.family.name)
                        .font(.caption)
                        .foregroundStyle(.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if self.showsBar {
                ThinBar(
                    fraction: Double(self.row.shownKilobytes) / self.largest,
                    color: emphasized ? .white : self.barColor)
                    .frame(width: 120)
            }

            Text(self.sizeText)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(self.row.isLive ? AnyShapeStyle(.primary) : self.row
                    .showsPrevious ? AnyShapeStyle(.muted) : AnyShapeStyle(.muted))
                .help(self.row.showsPrevious ? "From the last scan" : "")
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
                .contentTransition(.numericText())

            RowAction(row: self.row)
                .frame(width: 84)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .tableRowSelection(selected)
        .contentShape(Rectangle())
        .onTapGesture { self.model.selection = self.row.item }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(self.row.result?.label ?? self.row.item.name), "
                + "\(self.sizeText.isEmpty ? RowWords.state(self.row) : self.sizeText)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(Motion.animation(.easeInOut(duration: 0.4)), value: self.row.kilobytes)
    }

    private var barColor: Color {
        switch self.row.state {
        case .cleaned, .cleaning: Palette.cleaned
        case .measuring: Palette.color(self.row.item).opacity(0.6)
        case .waiting, .notMeasured: Palette.color(self.row.item).opacity(0.25)
        case .measured: Palette.color(self.row.item)
        }
    }

    private var sizeText: String {
        switch self.row.state {
        case .waiting: self.row.showsPrevious && self.row.shownKilobytes > 0 ? SizeText
            .of(kilobytes: self.row.shownKilobytes) : ""
        case .notMeasured: ""
        case .measuring: self.row.progressBytes > 0 ? SizeText.of(bytes: self.row.progressBytes) : ""
        case .cleaning, .cleaned: SizeText.of(kilobytes: self.row.kilobytes)
        case .measured:
            if !self.row.sizeKnown, self.row.kilobytes == 0 {
                "Unknown"
            } else if self.row.result?.isEmpty ?? true {
                "none"
            } else {
                SizeText.of(kilobytes: self.row.kilobytes)
            }
        }
    }
}

enum RowWords {
    /// What VoiceOver says for a row with no size yet.
    static func state(_ row: AppModel.Row) -> String {
        switch row.state {
        case .waiting: "waiting"
        case .measuring: "measuring"
        case .notMeasured: "not measured"
        default: ""
        }
    }
}

/// The trailing cell of a row: what can be done now, or what is happening.
struct RowAction: View {
    @Environment(AppModel.self) private var model
    let row: AppModel.Row

    var body: some View {
        switch self.row.state {
        case .waiting:
            Text("Waiting").font(.caption).foregroundStyle(.muted)
        case .measuring:
            Pulsing { Text("Measuring").font(.caption).foregroundStyle(.muted) }
        case .notMeasured:
            Text("Not measured").font(.caption).foregroundStyle(.muted)
        case .cleaning:
            ProgressView().controlSize(.small)
        case .cleaned:
            Text(self.row.canPutBack ? "In Trash" : "Deleted")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        case .measured:
            if self.row.isLive {
                Button("Clean") {
                    self.model.selection = self.row.item
                    Task { await self.model.requestClean([self.row.item]) }
                }
                .controlSize(.small)
                .disabled(self.model.isScanning || self.model.isCleaning)
            }
        }
    }
}

/// Fades its content in and out while it is shown.
struct Pulsing<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let content: Content

    var body: some View {
        if self.reduceMotion {
            self.content
        } else {
            PhaseAnimator([0.35, 1.0]) { opacity in
                self.content.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.6)
            }
        }
    }
}
