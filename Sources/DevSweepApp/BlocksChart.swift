import AppKit
import DevSweepKit
import SwiftUI

/// The live items as a squarified treemap, with the total and the families
/// beside it. Cells slide into place as items are measured and cleaned.
struct BlocksChart: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SizeText.of(kilobytes: self.model.reclaimableKilobytes))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(self.model
                        .isScanning ? (self.model.showsPrevious ? "updating" : "found so far") : "reclaimable")
                        .font(.callout)
                        .foregroundStyle(.muted)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Family.allCases) { family in
                        Button {
                            self.model.pick(family)
                        } label: {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2).fill(Palette.color(family)).frame(width: 8, height: 8)
                                Text(family.name).lineLimit(1).truncationMode(.tail)
                                Spacer(minLength: 4)
                                Text(self.model.measuredKilobytes(of: family).map { SizeText.of(kilobytes: $0) } ?? "–")
                                    .foregroundStyle(.muted)
                                    .monospacedDigit()
                            }
                            .font(.callout)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 150)

            GeometryReader { proxy in
                TreemapCells(size: proxy.size)
            }
        }
    }

    /// The gap around each cell.
    static let cellInset: CGFloat = 1.5
    /// The space between a cell's edge and its label.
    static let labelPadding = (horizontal: CGFloat(9), vertical: CGFloat(7))

    /// Whether a cell of `size` points has room for its label: the first four
    /// letters of the name (or all of a shorter one) over the size, inside
    /// the padding, measured in the fonts the label uses.
    static func fitsLabel(_ size: CGSize, name: String, sizeText: String) -> Bool {
        let nameFont = NSFont.systemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize,
            weight: .semibold)
        let sizeFont = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize,
            weight: .regular)
        let shortest = name.count <= 4 ? name : name.prefix(4) + "…"
        let width = max(Self.width(of: shortest, in: nameFont), Self.width(of: sizeText, in: sizeFont))
        let height = Self.lineHeight(of: nameFont) + Self.lineHeight(of: sizeFont)
        return size.width >= width + 2 * self.labelPadding.horizontal
            && size.height >= height + 2 * self.labelPadding.vertical
    }

    private static func width(of text: String, in font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func lineHeight(of font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    /// The cells as drawn, each inset by the gap. A cell too thin to hold
    /// the gap has no frame to draw (inset, it would be CGRect.null and land
    /// far from the chart), so it is left out.
    static func drawnCells<ID>(_ cells: [Treemap.Cell<ID>]) -> [Treemap.Cell<ID>] {
        cells.compactMap { cell in
            var drawn = cell
            drawn.frame = cell.frame.insetBy(dx: Self.cellInset, dy: Self.cellInset)
            guard !drawn.frame.isNull, drawn.frame.width >= 1, drawn.frame.height >= 1 else { return nil }
            return drawn
        }
    }
}

private struct TreemapCells: View {
    @Environment(AppModel.self) private var model
    let size: CGSize

    var body: some View {
        let rows = self.model.orderedRows
            .filter { $0.isLive || $0.isCounting || ($0.showsPrevious && $0.shownKilobytes > 0) }
        // Small items are drawn larger so they stay visible (`ChartScale`).
        let shares = ChartScale.shares(rows.map { Double($0.shownKilobytes) })
        let cells = Treemap.squarify(zip(rows, shares).map { (id: $0.item, weight: $1) }, in: self.size)
        ZStack(alignment: .topLeading) {
            if cells.isEmpty {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Palette.placeholder)
                    .overlay {
                        Text(self.model.isScanning ? "Measuring…" : "Nothing to clean")
                            .foregroundStyle(.muted)
                    }
            }
            ForEach(BlocksChart.drawnCells(cells), id: \.id) { cell in
                if let row = model.rows[cell.id] {
                    TreemapCell(row: row, frame: cell.frame, selected: self.model.selection == cell.id)
                }
            }
        }
        .frame(width: self.size.width, height: self.size.height, alignment: .topLeading)
        .animation(Motion.animation(.easeInOut(duration: 0.4)), value: cells.map(\.frame))
    }
}

private struct TreemapCell: View {
    @Environment(AppModel.self) private var model
    let row: AppModel.Row
    let frame: CGRect
    let selected: Bool

    var body: some View {
        let color = Palette.color(self.row.item)
        let size = SizeText.of(kilobytes: self.row.shownKilobytes)
        Button {
            self.model.selection = self.row.item
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if BlocksChart.fitsLabel(self.frame.size, name: self.row.item.shortName, sizeText: size) {
                    Text(self.row.item.shortName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(size)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, BlocksChart.labelPadding.horizontal)
            .padding(.vertical, BlocksChart.labelPadding.vertical)
            .frame(width: max(self.frame.width, 0), height: max(self.frame.height, 0), alignment: .topLeading)
            .background(color.opacity(self.selected ? 0.55 : 0.3), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                self.selected ? color : color.opacity(0.6),
                lineWidth: 1))
            .opacity(self.row.isLive ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(
            "\(self.row.item.name), "
                + "\(SizeText.of(kilobytes: self.row.shownKilobytes))\(self.row.showsPrevious ? ", last scan" : "")")
        .accessibilityLabel(
            "\(self.row.item.name), "
                + "\(SizeText.of(kilobytes: self.row.shownKilobytes))\(self.row.showsPrevious ? ", last scan" : "")")
        .accessibilityAddTraits(self.selected ? .isSelected : [])
        .offset(x: self.frame.minX, y: self.frame.minY)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
