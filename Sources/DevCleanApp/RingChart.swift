import Charts
import DevCleanKit
import SwiftUI

/// Two concentric rings: families inside, their items outside, with the
/// reclaimable total in the hole. Unmeasured items are drawn in a faint tone
/// so the ring is whole from the start and fills in.
struct RingChart: View {
    @Environment(AppModel.self) private var model

    /// The ring's diameter: 240 points when there is room, down to 150 in
    /// the narrowest center column, so the legend keeps its share.
    static func diameter(forWidth width: CGFloat) -> CGFloat {
        min(240, max(150, (width - 20) * 0.45))
    }

    /// Sized from the width it is given, never from what it last had: a view
    /// whose minimum follows its current width makes the window grow without end.
    var body: some View {
        GeometryReader { proxy in
            content(width: proxy.size.width)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func content(width: CGFloat) -> some View {
        let diameter = Self.diameter(forWidth: width)
        return HStack(spacing: diameter < 200 ? 18 : 28) {
            ZStack {
                Ring(segments: outerSegments, innerRatio: 0.75, inset: 1.6) { select($0) }
                    .frame(width: diameter, height: diameter)
                Ring(segments: innerSegments, innerRatio: 0.786, inset: 1.6) { select($0) }
                    .frame(width: diameter * 0.7, height: diameter * 0.7)
                VStack(spacing: 2) {
                    Text(SizeText.of(kilobytes: model.reclaimableKilobytes))
                        .font(.system(size: diameter < 200 ? 22 : 30, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                    Text(model.isScanning ? "found so far" : "reclaimable")
                        .font(diameter < 200 ? .caption : .callout)
                        .foregroundStyle(.secondary)
                }
                .frame(width: diameter * 0.5)
                .allowsHitTesting(false)
            }
            .frame(width: diameter, height: diameter)
            .animation(.easeInOut(duration: 0.4), value: model.reclaimableKilobytes)
            .animation(.easeInOut(duration: 0.25), value: model.selection)

            FamilyLegend(showsShare: width - diameter > 260)
                .frame(maxWidth: .infinity)
        }
    }

    private func select(_ id: String) {
        if let item = Item(rawValue: id) {
            model.selection = item
        } else if let family = Family(rawValue: id) {
            model.pick(family)
        }
    }

    private var selectedFamily: Family? { model.selection?.family }

    /// Items grouped by family, in palette order so segments keep their places.
    private var outerSegments: [Ring.Segment] {
        Family.allCases.flatMap { family in
            family.items.compactMap { item -> Ring.Segment? in
                guard let row = model.rows[item] else { return nil }
                return Ring.Segment(id: item.rawValue, weight: model.chartWeight(row), color: color(for: row))
            }
        }
    }

    private var innerSegments: [Ring.Segment] {
        Family.allCases.map { family in
            let rows = family.items.compactMap { model.rows[$0] }
            let weight = rows.reduce(0) { $0 + model.chartWeight($1) }
            let measured = rows.contains(where: \.wasMeasured)
            let reclaimable = rows.filter { $0.isLive || $0.state == .cleaned }
            let allCleaned = !reclaimable.isEmpty && reclaimable.allSatisfy { $0.state == .cleaned }
            let color: Color = if !measured {
                Palette.placeholder
            } else if allCleaned {
                Palette.cleaned
            } else if selectedFamily == nil || selectedFamily == family {
                Palette.color(family)
            } else {
                Palette.color(family).opacity(0.42)
            }
            return Ring.Segment(id: family.rawValue, weight: weight, color: color)
        }
    }

    private func color(for row: AppModel.Row) -> Color {
        switch row.state {
        case .waiting, .measuring, .notMeasured:
            return Palette.placeholder
        case .cleaning, .cleaned:
            return Palette.cleaned
        case .measured:
            if model.selection == nil || model.selection == row.item { return Palette.color(row.item) }
            return Palette.color(row.item).opacity(0.42)
        }
    }
}

/// One ring of sectors. Clicking a sector reports its id.
struct Ring: View {
    struct Segment: Identifiable {
        let id: String
        let weight: Double
        let color: Color
    }

    let segments: [Segment]
    let innerRatio: Double
    let inset: CGFloat
    let onSelect: (String) -> Void
    @State private var selectedValue: Double?

    var body: some View {
        let drawn = segments.contains { $0.weight > 0 }
            ? segments
            : [Segment(id: "empty", weight: 1, color: Palette.placeholder)]
        Chart(drawn) { segment in
            SectorMark(
                angle: .value("Size", segment.weight),
                innerRadius: .ratio(innerRatio),
                angularInset: inset
            )
            .foregroundStyle(segment.color)
            .cornerRadius(2)
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: $selectedValue)
        .onChange(of: selectedValue) { _, value in
            guard let value else { return }
            var running = 0.0
            for segment in drawn {
                running += segment.weight
                if value <= running {
                    if segment.id != "empty" { onSelect(segment.id) }
                    break
                }
            }
        }
    }
}

/// A thin stacked bar of the families, and one line per family with its share and size.
struct FamilyLegend: View {
    @Environment(AppModel.self) private var model
    var showsShare = true

    var body: some View {
        let total = Double(max(model.reclaimableKilobytes, 1))
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let live = Family.allCases.filter { model.kilobytes(of: $0) > 0 }
                let gaps = CGFloat(max(live.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    if live.isEmpty {
                        Capsule().fill(Palette.placeholder)
                    }
                    ForEach(live) { family in
                        Rectangle()
                            .fill(Palette.color(family))
                            .frame(width: max(0, proxy.size.width - gaps) * Double(model.kilobytes(of: family)) / total)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)

            VStack(spacing: 0) {
                ForEach(Family.allCases) { family in
                    let kilobytes = model.kilobytes(of: family)
                    let measured = model.measuredKilobytes(of: family) != nil
                    Button {
                        model.pick(family)
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3).fill(Palette.color(family)).frame(width: 10, height: 10)
                            Text(family.name).fontWeight(.medium).lineLimit(1)
                            Spacer(minLength: 4)
                            if showsShare {
                                Text(model.reclaimableKilobytes > 0 && measured ? "\(Int((Double(kilobytes) / total * 100).rounded()))%" : "")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)
                            }
                            Text(measured ? SizeText.of(kilobytes: kilobytes) : "–")
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: model.reclaimableKilobytes)
    }
}

