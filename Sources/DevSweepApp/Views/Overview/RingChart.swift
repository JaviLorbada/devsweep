import Charts
import DevSweepKit
import SwiftUI

/// Two concentric rings: families inside, their items outside, with the
/// reclaimable total in the hole. Unmeasured items are drawn in a faint tone
/// so the ring is whole from the start and fills in.
struct RingChart: View {
    @Environment(OverviewViewModel.self) private var overview
    @Environment(ScanModel.self) private var scan

    /// The ring's diameter: 240 points when there is room, down to 150 in
    /// the narrowest center column, so the legend keeps its share.
    static func diameter(forWidth width: CGFloat) -> CGFloat {
        min(240, max(150, (width - 20) * 0.45))
    }

    /// Sized from the width it is given, never from what it last had: a view
    /// whose minimum follows its current width makes the window grow without end.
    var body: some View {
        GeometryReader { proxy in
            self.content(width: proxy.size.width)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func content(width: CGFloat) -> some View {
        let diameter = Self.diameter(forWidth: width)
        let shares = self.itemShares
        return HStack(spacing: diameter < 200 ? 18 : 28) {
            ZStack {
                Ring(segments: self.outerSegments(shares), innerRatio: 0.75, inset: 1.6) { self.select($0) }
                    .frame(width: diameter, height: diameter)
                Ring(segments: self.innerSegments(shares), innerRatio: 0.786, inset: 1.6) { self.select($0) }
                    .frame(width: diameter * 0.7, height: diameter * 0.7)
                VStack(spacing: 2) {
                    Text(SizeText.of(kilobytes: self.scan.tally.reclaimableKilobytes))
                        .font(.system(size: diameter < 200 ? 22 : 30, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                    Text(self.scan
                        .isScanning ? (self.scan.tally.showsPrevious ? "updating" : "found so far") : "reclaimable")
                        .font(diameter < 200 ? .caption : .callout)
                        .foregroundStyle(.muted)
                }
                .frame(width: diameter * 0.5)
                .allowsHitTesting(false)
            }
            .frame(width: diameter, height: diameter)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Reclaimable space")
            .accessibilityValue(SizeText.of(kilobytes: self.scan.tally.reclaimableKilobytes))
            .accessibilityChildren { self.segmentElements }
            .animation(Motion.animation(.easeInOut(duration: 0.4)), value: self.scan.tally.reclaimableKilobytes)
            .animation(Motion.animation(.easeInOut(duration: 0.25)), value: self.overview.selection)

            FamilyLegend(showsShare: width - diameter > 260)
                .frame(maxWidth: .infinity)
        }
    }

    /// Each family, then its items, with their sizes, as VoiceOver reads the ring.
    private var segmentElements: some View {
        ForEach(Family.allCases) { family in
            Rectangle()
                .accessibilityLabel(self.familyLabel(family))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { self.overview.pick(family) }
            ForEach(family.items.filter { self.scan.rows[$0] != nil }) { item in
                let row = self.scan.rows[item]
                Rectangle()
                    .accessibilityLabel("\(item.name), \(row.map { SizeText.of(kilobytes: $0.shownKilobytes) } ?? "")")
                    .accessibilityAddTraits(self.overview.selection == item ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { self.overview.select(item) }
            }
        }
    }

    /// "Xcode, 143 MB", or "not measured" before the scan reaches it.
    private func familyLabel(_ family: Family) -> String {
        let size = self.scan.tally.measuredKilobytes(of: family).map { SizeText.of(kilobytes: $0) }
        return "\(family.name), \(size ?? "not measured")"
    }

    private func select(_ id: String) {
        if let item = Item(rawValue: id) {
            self.overview.select(item)
        } else if let family = Family(rawValue: id) {
            self.overview.pick(family)
        }
    }

    private var selectedFamily: Family? {
        self.overview.selection?.family
    }

    /// Each item's share of the ring, from its chart weight scaled so small
    /// items stay visible (`ChartScale`).
    private var itemShares: [Item: Double] {
        let rows = Family.allCases.flatMap { $0.items.compactMap { self.scan.rows[$0] } }
        let shares = ChartScale.shares(rows.map { self.scan.tally.chartWeight($0) })
        return Dictionary(uniqueKeysWithValues: zip(rows.map(\.item), shares))
    }

    /// Items grouped by family, in palette order so segments keep their places.
    private func outerSegments(_ shares: [Item: Double]) -> [Ring.Segment] {
        Family.allCases.flatMap { family in
            family.items.compactMap { item -> Ring.Segment? in
                guard let row = scan.rows[item] else { return nil }
                return Ring.Segment(id: item.rawValue, weight: shares[item] ?? 0, color: self.color(for: row))
            }
        }
    }

    /// Each family as the sum of its items' shares, so it spans exactly its
    /// items in the outer ring.
    private func innerSegments(_ shares: [Item: Double]) -> [Ring.Segment] {
        Family.allCases.map { family in
            let rows = family.items.compactMap { self.scan.rows[$0] }
            let weight = rows.reduce(0) { $0 + (shares[$1.item] ?? 0) }
            let measured = rows.contains { $0.wasMeasured || $0.isCounting }
            let previousOnly = self.scan.tally.familyShowsPrevious(family)
            let reclaimable = rows.filter { $0.isLive || $0.state == .cleaned }
            let allCleaned = !reclaimable.isEmpty && reclaimable.allSatisfy { $0.state == .cleaned }
            let color: Color = if previousOnly {
                Palette.color(family).opacity(0.25)
            } else if !measured {
                Palette.placeholder
            } else if allCleaned {
                Palette.cleaned
            } else if self.selectedFamily == nil || self.selectedFamily == family {
                Palette.color(family)
            } else {
                Palette.color(family).opacity(0.42)
            }
            return Ring.Segment(id: family.rawValue, weight: weight, color: color)
        }
    }

    private func color(for row: ScanModel.Row) -> Color {
        switch row.state {
        case .measuring where row.isCounting:
            return Palette.color(row.item).opacity(0.6)
        case .waiting where row.showsPrevious:
            return Palette.color(row.item).opacity(0.25)
        case .waiting, .measuring, .notMeasured:
            return Palette.placeholder
        case .cleaning, .cleaned:
            return Palette.cleaned
        case .measured:
            if self.overview.selection == nil || self.overview.selection == row.item { return Palette.color(row.item) }
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
        let drawn = self.segments.contains { $0.weight > 0 }
            ? self.segments
            : [Segment(id: "empty", weight: 1, color: Palette.placeholder)]
        Chart(drawn) { segment in
            SectorMark(
                angle: .value("Size", segment.weight),
                innerRadius: .ratio(self.innerRatio),
                angularInset: self.inset)
                .foregroundStyle(segment.color)
                .cornerRadius(2)
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: self.$selectedValue)
        .onChange(of: self.selectedValue) { _, value in
            guard let value else { return }
            var running = 0.0
            for segment in drawn {
                running += segment.weight
                if value <= running {
                    if segment.id != "empty" { self.onSelect(segment.id) }
                    break
                }
            }
        }
    }
}

/// A thin stacked bar of the families, and one line per family with its share and size.
///
/// The bar draws the families as the ring does, with small ones larger
/// (`ChartScale`); the percentages and sizes are exact.
struct FamilyLegend: View {
    @Environment(OverviewViewModel.self) private var overview
    @Environment(ScanModel.self) private var scan
    var showsShare = true

    var body: some View {
        let total = Double(max(scan.tally.reclaimableKilobytes, 1))
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let shares = self.scan.tally.familyChartShares
                let live = Family.allCases.filter { (shares[$0] ?? 0) > 0 }
                let gaps = CGFloat(max(live.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    if live.isEmpty {
                        Capsule().fill(Palette.placeholder)
                    }
                    ForEach(live) { family in
                        Rectangle()
                            .fill(Palette.color(family))
                            .frame(width: max(0, proxy.size.width - gaps) * (shares[family] ?? 0))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)

            VStack(spacing: 0) {
                ForEach(Family.allCases) { family in
                    let kilobytes = self.scan.tally.kilobytes(of: family)
                    let measured = self.scan.tally.measuredKilobytes(of: family) != nil
                    Button {
                        self.overview.pick(family)
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3).fill(Palette.color(family)).frame(width: 10, height: 10)
                            Text(family.name).fontWeight(.medium).lineLimit(1)
                            Spacer(minLength: 4)
                            if self.showsShare {
                                Text(self.scan.tally
                                    .reclaimableKilobytes > 0 && measured ?
                                    "\(Int((Double(kilobytes) / total * 100).rounded()))%" : "")
                                    .font(.callout)
                                    .foregroundStyle(.muted)
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
        .animation(Motion.animation(.easeInOut(duration: 0.4)), value: self.scan.tally.reclaimableKilobytes)
    }
}
