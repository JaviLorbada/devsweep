import DevCleanKit
import SwiftUI

/// The eleven items, largest first: mark, color, name, a proportional bar,
/// size and what can be done with it.
struct ItemsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let rows = model.orderedRows
        let largest = Double(max(rows.map(\.kilobytes).max() ?? 1, 1))
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Items").fontWeight(.semibold)
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Mark all") { model.markAll() }
                Button("Mark none") { model.markNone() }
            }
            .buttonStyle(.link)
            .font(.callout)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)

            ForEach(rows) { row in
                Divider().opacity(0.6)
                ItemRow(row: row, largest: largest)
            }
        }
        .card()
    }

    private var note: String {
        let count = model.scanOrder.count
        return model.isScanning ? "\(model.measuredCount) of \(count) measured, largest first" : "\(count), largest first"
    }
}

struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let row: AppModel.Row
    let largest: Double

    var body: some View {
        let selected = model.selection == row.item
        HStack(spacing: 12) {
            Toggle("Mark \(row.item.name) for cleaning", isOn: Binding(
                get: { model.marked.contains(row.item) && row.isLive },
                set: { model.setMarked(row.item, $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!row.isLive)

            Dot(color: Palette.color(row.item))

            Button {
                model.selection = row.item
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.result?.label ?? row.item.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
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

            ThinBar(fraction: row.wasMeasured ? Double(row.kilobytes) / largest : 0,
                    color: row.state == .cleaned ? Palette.cleaned : Palette.color(row.item))
                .frame(width: 120)

            Text(sizeText)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(row.isLive ? .primary : .secondary)
                .frame(width: 64, alignment: .trailing)
                .contentTransition(.numericText())

            RowAction(row: row)
                .frame(width: 84)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(selected ? Color.accentColor.opacity(0.14) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { model.selection = row.item }
        .animation(.easeInOut(duration: 0.4), value: row.kilobytes)
    }

    private var sizeText: String {
        switch row.state {
        case .waiting, .notMeasured: ""
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
