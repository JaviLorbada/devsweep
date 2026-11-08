import DevSweepKit
import SwiftUI

/// The selected item: what it is, where it lives, what cleaning it does, and
/// for DerivedData what is inside.
struct ItemInspector: View {
    @Environment(OverviewViewModel.self) private var overview
    @Environment(ScanModel.self) private var scan

    var body: some View {
        if let item = overview.selection, let row = scan.rows[item] {
            ScrollView {
                // A fresh one per item, so a list expanded for one item
                // starts short for the next.
                ItemDetails(row: row)
                    .id(item)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .safeAreaBar(edge: .bottom) {
                InspectorAction(row: row)
                    .padding(18)
            }
        } else {
            ContentUnavailableView(
                "Nothing selected",
                systemImage: "sidebar.trailing",
                description: Text("Select an item to see what it holds."))
        }
    }
}

/// Everything the inspector says about one item.
struct ItemDetails: View {
    @Environment(ScanModel.self) private var scan
    @Environment(CleaningModel.self) private var cleaning
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let row: ScanModel.Row
    /// Whether the Where list shows every path rather than the first few.
    @State private var showsAllPaths = false

    static let pathsShown = 8

    var body: some View {
        let item = self.row.item
        VStack(alignment: .leading, spacing: 14) {
            self.header(self.row)
            self.location(self.row)
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "What happens")
                Text(item.whatHappens)
                    .font(.callout)
                    .foregroundStyle(.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Shown empty too after its parts went, to say so and put them back.
            if let result = row.shownResult, row.wasMeasured || row.showsPrevious, PartsList.lists(result),
               !result.isEmpty || self.cleaning.lastPartsClean(of: item) != nil
            {
                PartsList(
                    result: result,
                    color: Palette.color(item),
                    selectable: self.row.result != nil && [.measured, .cleaning].contains(self.row.state))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, WindowLayout.inspectorTopPadding)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ row: ScanModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Dot(color: Palette.color(row.item.family))
                Eyebrow(text: row.item.family.name)
            }
            Text(row.shownResult?.label ?? row.item.name)
                .font(.title3.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(self.heroSize(row))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(self.stateWord(row))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(row.state == .cleaned ? AnyShapeStyle(.green) : AnyShapeStyle(.muted))
            }
        }
    }

    private func location(_ row: ScanModel.Row) -> some View {
        let paths = row.shownResult?.paths ?? []
        return VStack(alignment: .leading, spacing: 5) {
            Eyebrow(text: "Where")
            Text(row.shownResult?.location ?? "")
                .font(.caption.monospaced())
                .foregroundStyle(.muted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            // A build item's folders are listed with their sizes further down.
            if paths.count > 1, !(row.shownResult.map(PartsList.listsFolders) ?? false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(self.showsAllPaths ? paths : Array(paths.prefix(Self.pathsShown)), id: \.self) { path in
                        Text(self.scan.tilde(path))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(self.scan.tilde(path))
                    }
                    if paths.count > Self.pathsShown {
                        Button(self.showsAllPaths ? "Show fewer" : "and \(paths.count - Self.pathsShown) more") {
                            withAnimation(self.reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                self.showsAllPaths.toggle()
                            }
                        }
                        .buttonStyle(.link)
                        .font(.caption2)
                        .accessibilityHint(self
                            .showsAllPaths ? "Hides all but the first \(Self.pathsShown) paths" : "Shows every path")
                    }
                }
            }
            if !paths.isEmpty {
                Button("Reveal in Finder") { Finder.reveal(paths) }
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
    }

    private func heroSize(_ row: ScanModel.Row) -> String {
        switch row.state {
        case .waiting: row.showsPrevious ? SizeText.of(kilobytes: row.shownKilobytes) : "–"
        case .notMeasured: "–"
        case .measuring: SizeText.of(bytes: row.progressBytes)
        case .measured: !row.sizeKnown && row.kilobytes == 0 ? "?" : SizeText.of(kilobytes: row.kilobytes)
        case .cleaning: SizeText.of(kilobytes: row.leftKilobytes)
        case .cleaned: SizeText.of(kilobytes: row.kilobytes)
        }
    }

    private func stateWord(_ row: ScanModel.Row) -> String {
        switch row.state {
        case .waiting: row.showsPrevious ? "last scan, waiting" : "waiting"
        case .measuring: "measuring"
        case .notMeasured: "not measured"
        case .cleaning: row.cleaningProgress == nil ? "cleaning" : "left to delete"
        case .cleaned: row.canPutBack ? "in Trash" : "deleted"
        case .measured:
            if !row.sizeKnown {
                "size unknown"
            } else if row.result?.isEmpty ?? true {
                "nothing to clean"
            } else {
                "reclaimable"
            }
        }
    }
}

/// The inspector's bottom button: Clean, Put back, or a disabled Measuring.
struct InspectorAction: View {
    @Environment(ScanModel.self) private var scan
    @Environment(MarksModel.self) private var marks
    @Environment(CleaningModel.self) private var cleaning
    let row: ScanModel.Row

    var body: some View {
        switch self.row.state {
        case .waiting, .measuring:
            self.wide(Button("Measuring") {}.buttonStyle(.prominentAction).disabled(true))
        case .measured where self.row.isLive && !self.marks.markedParts(of: self.row.item).isEmpty:
            let item = self.row.item
            let marked = self.marks.markedParts(of: item)
            let parts = "\(CleanPrompt.partsSummary(marked, in: item)), "
                + SizeText.of(kilobytes: self.scan.kilobytes(of: marked, in: item))
            self.wide(Button("Clean \(parts)") {
                Task { await self.cleaning.requestCleanParts(of: item) }
            }
            .buttonStyle(.prominentAction)
            .disabled(self.scan.isScanning || self.scan.isCleaning))
        case .measured where self.row.isLive:
            self.wide(Button("Clean \(self.row.item.shortName)") {
                Task { await self.cleaning.requestClean([self.row.item]) }
            }
            .buttonStyle(.prominentAction)
            .disabled(self.scan.isScanning || self.scan.isCleaning))
        case .cleaning:
            self.wide(Button("Cleaning") {}.buttonStyle(.glass).disabled(true))
        case .cleaned where self.row.canPutBack:
            self.wide(Button("Put Back") {
                Task { await self.cleaning.putBack(self.row.item) }
            }
            .buttonStyle(.glass)
            .help("Move it from the Trash back where it was"))
        default:
            EmptyView()
        }
    }

    private func wide(_ button: some View) -> some View {
        button
            .controlSize(.large)
            .frame(maxWidth: .infinity)
    }
}
