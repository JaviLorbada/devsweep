import DevSweepKit
import SwiftUI

/// The eleven items, largest first: mark, color, name, a proportional bar,
/// size and what can be done with it.
struct ItemsCard: View {
    @Environment(OverviewViewModel.self) private var overview
    @Environment(ScanModel.self) private var scan
    @Environment(MarksModel.self) private var marks
    @Environment(CleaningModel.self) private var cleaning
    let contrast: ChartContrast

    /// The bar is the first column to go when the center column narrows.
    static func showsBar(forWidth width: CGFloat) -> Bool { width >= 600 }

    static let headerHeight: CGFloat = 34
    static let rowHeight: CGFloat = 33

    /// Sized from the width it is given (its height is fixed by its rows), so
    /// its minimum never follows the width it last had.
    var body: some View {
        let rows = self.scan.tally.ordered
        GeometryReader { proxy in
            self.table(rows: rows, showsBar: Self.showsBar(forWidth: proxy.size.width))
        }
        .frame(height: Self.headerHeight + CGFloat(rows.count) * Self.rowHeight)
        .card()
        // The last row's selection follows the card's corners.
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func table(rows: [ScanRow], showsBar: Bool) -> some View {
        let largest = Double(max(rows.map(\.shownKilobytes).max() ?? 1, 1))
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Items").fontWeight(.semibold).layoutPriority(1).accessibilityAddTraits(.isHeader)
                Text(self.note)
                    .font(.callout)
                    .foregroundStyle(.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Mark all") { self.marks.markAll() }
                Button("Mark none") { self.marks.markNone() }
            }
            .buttonStyle(.link)
            .font(.callout)
            .padding(.horizontal, 14)
            .frame(height: Self.headerHeight)

            ForEach(rows) { row in
                let marked = row.isLive && self.marks.marked.contains(row.item)
                Divider().opacity(0.6)
                ItemRow(
                    row: row,
                    largest: largest,
                    marked: marked,
                    canClean: row.isLive && !self.scan.isScanning && !self.scan.isCleaning,
                    spoken: SpokenText.row(row, marked: marked, in: self.scan.tally),
                    contrast: self.contrast,
                    showsBar: showsBar,
                    clean: { self.clean(row.item) })
            }
        }
    }

    /// What a row's Clean does, by its button or VoiceOver's action.
    private func clean(_ item: Item) {
        self.overview.select(item)
        Task {
            await self.cleaning.requestClean([item])
        }
    }

    private var note: String {
        let count = self.scan.scanOrder.count
        return self.scan.isScanning ? "\(self.scan.tally.measuredCount) of \(count) measured, largest "
            + "first" : "\(count), largest first"
    }
}

/// One item: its mark, name, bar, size and action. For VoiceOver and the
/// keyboard it is one element, as a table row is: Space or VoiceOver's
/// press marks it, focusing it selects it, and its actions select and clean it.
struct ItemRow: View {
    @Environment(OverviewViewModel.self) private var overview
    @Environment(MarksModel.self) private var marks
    @Environment(\.appearsActive) private var appearsActive
    @FocusState private var focused: Bool
    let row: ScanRow
    let largest: Double
    /// Whether it is ticked; never while it has nothing to clean.
    let marked: Bool
    let canClean: Bool
    let spoken: SpokenText
    let contrast: ChartContrast
    var showsBar = true
    let clean: () -> Void

    var body: some View {
        let selected = self.overview.selection == self.row.item
        // On the selection color, marks turn white like a table's icons, or a
        // dark blue item would vanish on it.
        let emphasized = selected && self.appearsActive
        HStack(spacing: 12) {
            Toggle("Mark \(self.row.item.name) for cleaning", isOn: Binding(
                get: { self.marked },
                set: { self.marks.setMarked(self.row.item, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!self.row.isLive)
                // The row takes the keyboard's focus and Space, so the box
                // isn't a second stop.
                .focusable(false)

            Dot(color: emphasized ? .white : Palette.color(self.row.item))

            HStack(spacing: 0) {
                // The family shows whole or not at all: cut down beside a
                // long name in a narrow window, it was a stray letter.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        self.name
                        Text(self.row.item.family.name)
                            .font(.caption)
                            .foregroundStyle(.muted)
                            .lineLimit(1)
                    }
                    self.name
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)

            if self.showsBar {
                ThinBar(
                    fraction: Double(self.row.state == .cleaning ? self.row.leftKilobytes : self.row.shownKilobytes)
                        / self.largest,
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

            RowAction(row: self.row, canClean: self.canClean, clean: self.clean)
                .frame(width: 84)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .tableRowSelection(selected)
        .contentShape(Rectangle())
        .onTapGesture { self.overview.select(self.row.item) }
        .focusable()
        .focused(self.$focused)
        .onChange(of: self.focused) { _, focused in
            if focused {
                self.overview.select(self.row.item)
            }
        }
        .onKeyPress(.space) {
            self.toggleMark()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .spoken(self.spoken)
        .accessibilityAddTraits(self.traits(selected: selected))
        .accessibilityAction { self.toggleMark() }
        // SwiftUI lists the last added first: Select, then Clean.
        .accessibilityActions {
            if self.canClean {
                Button("Clean") { self.clean() }
            }
        }
        .accessibilityAction(named: "Select") { self.overview.select(self.row.item) }
        .animation(Motion.animation(.easeInOut(duration: 0.4)), value: self.row.kilobytes)
    }

    /// A toggle while it can be marked; selected while the inspector shows it.
    private func traits(selected: Bool) -> AccessibilityTraits {
        let toggle: AccessibilityTraits = self.row.isLive ? .isToggle : []
        return selected ? toggle.union(.isSelected) : toggle
    }

    private func toggleMark() {
        guard self.row.isLive else {
            return
        }
        self.marks.toggle(self.row.item)
    }

    private var name: some View {
        Text(self.row.result?.label ?? self.row.item.name)
            .fontWeight(.medium)
            .lineLimit(1)
    }

    private var barColor: Color {
        switch self.row.state {
        case .cleaned, .cleaning: self.contrast.cleaned
        case .measuring: Palette.color(self.row.item).opacity(self.contrast.measuring)
        case .waiting, .notMeasured: Palette.color(self.row.item).opacity(self.contrast.lastScan)
        case .measured: Palette.color(self.row.item)
        }
    }

    private var sizeText: String {
        switch self.row.state {
        case .waiting: self.row.showsPrevious && self.row.shownKilobytes > 0 ? SizeText
            .of(kilobytes: self.row.shownKilobytes) : ""
        case .notMeasured: ""
        case .measuring: self.row.progressBytes > 0 ? SizeText.of(bytes: self.row.progressBytes) : ""
        case .cleaning: SizeText.of(kilobytes: self.row.leftKilobytes)
        case .cleaned: SizeText.of(kilobytes: self.row.kilobytes)
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

/// The trailing cell of a row: what can be done now, or what is happening.
struct RowAction: View {
    let row: ScanRow
    let canClean: Bool
    let clean: () -> Void

    var body: some View {
        switch self.row.state {
        case .waiting:
            Text("Waiting").font(.caption).foregroundStyle(.muted)
        case .measuring:
            Pulsing { Text("Measuring").font(.caption).foregroundStyle(.muted) }
        case .notMeasured:
            Text("Not measured").font(.caption).foregroundStyle(.muted)
        case .cleaning:
            if let progress = self.row.cleaningProgress {
                ProgressView(value: progress).progressViewStyle(.circular).controlSize(.small)
            } else {
                ProgressView().controlSize(.small)
            }
        case .cleaned:
            Text(self.row.canPutBack ? "In Trash" : "Deleted")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        case .measured:
            if self.row.isLive {
                Button("Clean", action: self.clean)
                    .controlSize(.small)
                    .rowControl()
                    .disabled(!self.canClean)
                    // The row is the stop; VoiceOver has Clean as the row's action.
                    .focusable(false)
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
