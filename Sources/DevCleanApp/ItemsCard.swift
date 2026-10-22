import DevCleanKit
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
        let rows = model.orderedRows
        GeometryReader { proxy in
            table(rows: rows, showsBar: Self.showsBar(forWidth: proxy.size.width))
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
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Mark all") { model.markAll() }
                Button("Mark none") { model.markNone() }
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
        let count = model.scanOrder.count
        return model.isScanning ? "\(model.measuredCount) of \(count) measured, largest first" : "\(count), largest first"
    }
}

struct ItemRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appearsActive) private var appearsActive
    let row: AppModel.Row
    let largest: Double
    var showsBar = true

    var body: some View {
        let selected = model.selection == row.item
        // On the selection color, marks turn white like a table's icons, or a
        // dark blue item would vanish on it.
        let emphasized = selected && appearsActive
        HStack(spacing: 12) {
            Toggle("Mark \(row.item.name) for cleaning", isOn: Binding(
                get: { model.marked.contains(row.item) && row.isLive },
                set: { model.setMarked(row.item, $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!row.isLive)

            Dot(color: emphasized ? .white : Palette.color(row.item))

            Button {
                model.selection = row.item
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.result?.label ?? row.item.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(row.item.family.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsBar {
                ThinBar(fraction: Double(row.shownKilobytes) / largest, color: emphasized ? .white : barColor)
                    .frame(width: 120)
            }

            Text(sizeText)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(row.isLive ? AnyShapeStyle(.primary) : row.showsPrevious ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .help(row.showsPrevious ? "From the last scan" : "")
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
                .contentTransition(.numericText())

            RowAction(row: row)
                .frame(width: 84)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        // Selected the way a macOS table selects: the whole row, edge to edge,
        // in the selection color while the window is active and gray when not,
        // with text that turns light on the color.
        .environment(\.backgroundProminence, emphasized ? .increased : .standard)
        .background {
            if selected {
                Rectangle().fill(Color(nsColor: appearsActive ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selection = row.item }
        .animation(.easeInOut(duration: 0.4), value: row.kilobytes)
    }

    private var barColor: Color {
        switch row.state {
        case .cleaned, .cleaning: Palette.cleaned
        case .measuring: Palette.color(row.item).opacity(0.6)
        case .waiting, .notMeasured: Palette.color(row.item).opacity(0.25)
        case .measured: Palette.color(row.item)
        }
    }

    private var sizeText: String {
        switch row.state {
        case .waiting: row.showsPrevious && row.shownKilobytes > 0 ? SizeText.of(kilobytes: row.shownKilobytes) : ""
        case .notMeasured: ""
        case .measuring: row.progressBytes > 0 ? SizeText.of(bytes: row.progressBytes) : ""
        case .cleaning, .cleaned: SizeText.of(kilobytes: row.kilobytes)
        case .measured:
            if !row.sizeKnown && row.kilobytes == 0 { "Unknown" }
            else if row.result?.isEmpty ?? true { "none" }
            else { SizeText.of(kilobytes: row.kilobytes) }
        }
    }
}

/// The trailing cell of a row: what can be done now, or what is happening.
struct RowAction: View {
    @Environment(AppModel.self) private var model
    let row: AppModel.Row

    var body: some View {
        switch row.state {
        case .waiting:
            Text("Waiting").font(.caption).foregroundStyle(.secondary)
        case .measuring:
            Pulsing { Text("Measuring").font(.caption).foregroundStyle(.secondary) }
        case .notMeasured:
            Text("Not measured").font(.caption).foregroundStyle(.secondary)
        case .cleaning:
            ProgressView().controlSize(.small)
        case .cleaned:
            Text(row.canPutBack ? "In Trash" : "Deleted")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        case .measured:
            if row.isLive {
                Button("Clean") {
                    model.selection = row.item
                    Task { await model.requestClean([row.item]) }
                }
                .controlSize(.small)
                .disabled(model.isScanning || model.isCleaning)
            }
        }
    }
}

/// Fades its content in and out while it is shown.
struct Pulsing<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        PhaseAnimator([0.35, 1.0]) { opacity in
            content.opacity(opacity)
        } animation: { _ in
            .easeInOut(duration: 0.6)
        }
    }
}
