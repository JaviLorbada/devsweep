import DevCleanKit
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
}

private struct TreemapCells: View {
    @Environment(AppModel.self) private var model
    let size: CGSize

    var body: some View {
        let rows = self.model.orderedRows
            .filter { $0.isLive || $0.isCounting || ($0.showsPrevious && $0.shownKilobytes > 0) }
        let cells = Treemap.squarify(rows.map { (id: $0.item, weight: Double($0.shownKilobytes)) }, in: self.size)
        ZStack(alignment: .topLeading) {
            if cells.isEmpty {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Palette.placeholder)
                    .overlay {
                        Text(self.model.isScanning ? "Measuring…" : "Nothing to clean")
                            .foregroundStyle(.muted)
                    }
            }
            ForEach(cells, id: \.id) { cell in
                if let row = model.rows[cell.id] {
                    TreemapCell(
                        row: row,
                        frame: cell.frame.insetBy(dx: 1.5, dy: 1.5),
                        selected: self.model.selection == cell.id)
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
        Button {
            self.model.selection = self.row.item
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if self.frame.width >= 78, self.frame.height >= 36 {
                    Text(self.row.item.shortName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(SizeText.of(kilobytes: self.row.shownKilobytes))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.muted)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
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
            "\(self.row.item.name), \(SizeText.of(kilobytes: self.row.shownKilobytes))\(self.row.showsPrevious ? ", last scan" : "")")
        .accessibilityLabel(
            "\(self.row.item.name), \(SizeText.of(kilobytes: self.row.shownKilobytes))\(self.row.showsPrevious ? ", last scan" : "")")
        .accessibilityAddTraits(self.selected ? .isSelected : [])
        .offset(x: self.frame.minX, y: self.frame.minY)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
