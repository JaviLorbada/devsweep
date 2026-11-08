import DevSweepKit
import SwiftUI

// The screens for things DevSweep lists but never deletes on its own:
// simulator runtimes, which can be removed one at a time after a
// confirmation, and installed Xcodes, which can only be revealed in Finder.

struct SimulatorRuntimesView: View {
    var body: some View {
        ScrollView { RuntimesContent() }
    }
}

struct XcodeVersionsView: View {
    var body: some View {
        ScrollView { XcodesContent() }
    }
}

/// Runtimes, then the installed Xcodes, as on the Extras board.
struct RuntimesContent: View {
    @Environment(RuntimesViewModel.self) private var runtimes
    @Environment(ScanModel.self) private var scan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExtrasCard(
                title: "Runtimes",
                note: "flagged after \(self.runtimes.staleDays) days unused or with no simulators",
                rowCount: self.scan.extras?.runtimes.count ?? 0)
            {
                if let runtimes = scan.extras?.runtimes, !runtimes.isEmpty {
                    let largest = Double(runtimes.map(\.kilobytes).max() ?? 1)
                    ForEach(runtimes) { runtime in
                        Divider().opacity(0.6)
                        RuntimeRow(runtime: runtime, largest: largest)
                    }
                } else {
                    EmptyExtrasRow(text: self.scan
                        .isLoadingExtras ? "Listing runtimes…" : "No simulator runtimes found.")
                }
            }
            XcodesCard()
            ArchivesNote()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
}

struct XcodesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            XcodesCard()
            ArchivesNote()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
}

private struct ArchivesNote: View {
    var body: some View {
        Text("Xcode Archives are never listed: their dSYMs symbolicate crash reports.")
            .font(.callout)
            .foregroundStyle(.muted)
    }
}

private struct XcodesCard: View {
    @Environment(ScanModel.self) private var scan

    var body: some View {
        let xcodes = self.scan.extras?.xcodes ?? []
        ExtrasCard(
            title: "Xcode versions",
            note: xcodes.count > 1 ? "each keeps its own compilation cache in DerivedData" : "",
            rowCount: xcodes.count)
        {
            if xcodes.isEmpty {
                EmptyExtrasRow(text: self.scan
                    .isLoadingExtras ? "Listing Xcodes…" : "No Xcode found in the applications folders.")
            } else {
                let largest = Double(xcodes.map(\.kilobytes).max() ?? 1)
                ForEach(xcodes) { xcode in
                    Divider().opacity(0.6)
                    XcodeRow(xcode: xcode, largest: largest)
                }
            }
        }
    }
}

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

private struct RuntimeRow: View {
    @Environment(WindowViewModel.self) private var window
    @Environment(RuntimesViewModel.self) private var runtimes
    @Environment(\.extrasColumns) private var columns
    let runtime: SimulatorRuntime
    let largest: Double

    var body: some View {
        let reason = self.runtime.flagReason(staleDays: self.runtimes.staleDays)
        let selected = self.window.screen == .simulatorRuntimes && self.runtimes.current?.id == self.runtime.id
        let tint: Color = reason == nil ? .secondary.opacity(0.6) : .orange
        HStack(spacing: 12) {
            Dot(color: tint)
            // Everything here can shrink: the badge or count gives way first,
            // then the title truncates.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.runtime.title).fontWeight(.medium).lineLimit(1).layoutPriority(2)
                if let reason {
                    Badge(text: RuntimeWords.badge(self.runtime, staleDays: self.runtimes.staleDays), color: .orange)
                        .help(reason)
                } else {
                    Text(self.runtime.simulatorCount == 1 ? "1 simulator" : "\(self.runtime.simulatorCount) simulators")
                        .font(.caption)
                        .foregroundStyle(.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if self.columns.showsDate {
                Text(self.runtime.lastUsedDay.map { "used \($0)" } ?? "never used")
                    .font(.callout)
                    .foregroundStyle(.muted)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)
            }
            if self.columns.showsBar {
                ThinBar(fraction: Double(self.runtime.kilobytes) / max(self.largest, 1), color: tint)
                    .frame(width: 100)
            }
            Text(SizeText.of(kilobytes: self.runtime.kilobytes))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
            Group {
                if reason == nil {
                    Color.clear
                } else if self.columns == .compact {
                    Button("Remove Runtime", systemImage: "trash") {
                        self.runtimes.askToRemove(self.runtime)
                    }
                    .labelStyle(.iconOnly)
                    .help("Remove Runtime")
                } else {
                    Button("Remove Runtime") {
                        self.runtimes.askToRemove(self.runtime)
                    }
                }
            }
            .controlSize(.small)
            .rowControl()
            .frame(width: self.columns == .compact ? 28 : 118)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .tableRowSelection(selected)
        .contentShape(Rectangle())
        .onTapGesture { self.runtimes.select(self.runtime) }
        .focusable()
        .onKeyPress(.space) { self.runtimes.select(self.runtime); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(self.runtime.title), \(SizeText.of(kilobytes: self.runtime.kilobytes))\(reason.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Select") { self.runtimes.select(self.runtime) }
    }
}

private struct XcodeRow: View {
    @Environment(WindowViewModel.self) private var window
    @Environment(XcodesViewModel.self) private var xcodes
    @Environment(ScanModel.self) private var scan
    @Environment(\.extrasColumns) private var columns
    let xcode: InstalledXcode
    let largest: Double

    var body: some View {
        let selected = self.window.screen == .xcodeVersions && self.xcodes.current?.path == self.xcode.path
        HStack(spacing: 12) {
            Dot(color: .secondary.opacity(0.6))
            // Everything here can shrink: the path gives way first, then the
            // title truncates. Nothing in a row may insist on its full width.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.xcode.title).fontWeight(.medium).lineLimit(1).layoutPriority(2)
                if self.xcode.isSelected { Badge(text: "selected", color: .accentColor).layoutPriority(2) }
                if self.columns != .compact {
                    Text(self.scan.tilde(self.xcode.path))
                        .font(.caption.monospaced())
                        .foregroundStyle(.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if self.columns.showsDate {
                Text(self.xcode.lastOpened.map { "opened \(DayFormat.utc($0))" } ?? "last opened unknown")
                    .font(.callout)
                    .foregroundStyle(.muted)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)
            }
            if self.columns.showsBar {
                ThinBar(fraction: Double(self.xcode.kilobytes) / max(self.largest, 1), color: .secondary.opacity(0.6))
                    .frame(width: 100)
            }
            Text(SizeText.of(kilobytes: self.xcode.kilobytes))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
            Group {
                if self.columns == .compact {
                    Button("Reveal in Finder", systemImage: "folder") { Finder.reveal([self.xcode.path]) }
                        .labelStyle(.iconOnly)
                        .controlSize(.small)
                        .help("Reveal in Finder")
                } else {
                    Button("Reveal in Finder") { Finder.reveal([self.xcode.path]) }
                        .controlSize(.small)
                        .frame(width: 118)
                }
            }
            .rowControl()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .tableRowSelection(selected)
        .contentShape(Rectangle())
        .onTapGesture { self.xcodes.select(self.xcode) }
        .focusable()
        .onKeyPress(.space) { self.xcodes.select(self.xcode); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(self.xcode.title), \(SizeText.of(kilobytes: self.xcode.kilobytes))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Select") { self.xcodes.select(self.xcode) }
    }
}

// MARK: Inspectors

struct RuntimeInspector: View {
    @Environment(RuntimesViewModel.self) private var runtimes
    @Environment(ScanModel.self) private var scan

    var body: some View {
        if let runtime = runtimes.current {
            // Scrolls, so the column never asks the window for the height of
            // its text: at a small width that would be thousands of points.
            ScrollView {
                RuntimeDetails(runtime: runtime)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .safeAreaBar(edge: .bottom) {
                Button("Remove Runtime") { self.runtimes.removal.ask(runtime) }
                    .buttonStyle(.prominentAction)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(18)
            }
        } else {
            ContentUnavailableView(
                "No runtime",
                systemImage: "iphone",
                description: Text(self.scan
                    .isLoadingExtras ? "Listing runtimes…" : "No simulator runtimes found."))
        }
    }
}

/// What the inspector says about one runtime.
struct RuntimeDetails: View {
    @Environment(RuntimesViewModel.self) private var runtimes
    let runtime: SimulatorRuntime

    var body: some View {
        let reason = self.runtime.flagReason(staleDays: self.runtimes.staleDays)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Dot(color: reason == nil ? .secondary.opacity(0.6) : .orange)
                Eyebrow(text: "Simulator runtime")
            }
            Text(self.runtime.title).font(.title3.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(SizeText.of(kilobytes: self.runtime.kilobytes))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                Text(reason == nil ? "in use" : "looks unused")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(reason == nil ? AnyShapeStyle(.muted) : AnyShapeStyle(.orange))
            }
            Section(reason == nil ? "Usage" : "Why it is flagged") {
                Text(RuntimeWords.usage(self.runtime, staleDays: self.runtimes.staleDays))
            }
            Section("What happens") {
                Text(RuntimeWords.whatHappens(self.runtime))
            }
            Section("Runs") {
                Text(self.runtime.removalCommand)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, WindowLayout.inspectorTopPadding)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private struct Section<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content

        init(_ title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: self.title)
                self.content
                    .font(.callout)
                    .foregroundStyle(.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct XcodeInspector: View {
    @Environment(XcodesViewModel.self) private var xcodes
    @Environment(ScanModel.self) private var scan

    var body: some View {
        if let xcode = xcodes.current {
            // Scrolls, so the column never asks the window for the height of
            // its text: at a small width that would be thousands of points.
            ScrollView {
                XcodeDetails(xcode: xcode, installedCount: self.scan.extras?.xcodes.count ?? 0)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .safeAreaBar(edge: .bottom) {
                Button("Reveal in Finder") { Finder.reveal([xcode.path]) }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(18)
            }
        } else {
            ContentUnavailableView(
                "No Xcode",
                systemImage: "hammer",
                description: Text(self.scan
                    .isLoadingExtras ? "Listing Xcodes…" :
                    "No Xcode found in the applications folders."))
        }
    }
}

/// What the inspector says about one Xcode.
struct XcodeDetails: View {
    @Environment(ScanModel.self) private var scan
    let xcode: InstalledXcode
    let installedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Dot(color: .secondary.opacity(0.6))
                Eyebrow(text: "Xcode")
            }
            Text(self.xcode.title).font(.title3.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(SizeText.of(kilobytes: self.xcode.kilobytes))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                Text(self.xcode.isSelected ? "selected" : "installed")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.muted)
            }
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "Where")
                Text(self.scan.tilde(self.xcode.path))
                    .font(.caption.monospaced())
                    .foregroundStyle(.muted)
                    .textSelection(.enabled)
                Text(self.xcode.lastOpened
                    .map { "Last opened \(DayFormat.utc($0))." } ?? "Spotlight doesn't know when it was last opened.")
                    .font(.callout)
                    .foregroundStyle(.muted)
            }
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "What happens")
                Text(XcodeWords.note(self.xcode, installedCount: self.installedCount))
                    .font(.callout)
                    .foregroundStyle(.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, WindowLayout.inspectorTopPadding)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: Removing a runtime

/// The confirmation before removing a runtime, showing the exact command.
struct RemoveRuntimeSheet: View {
    @Environment(RuntimesViewModel.self) private var runtimes
    @Environment(\.dismiss) private var dismiss
    let runtime: SimulatorRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remove \(self.runtime.title)?")
                .font(.title3.weight(.semibold))
            Text(
                "This frees \(SizeText.of(kilobytes: self.runtime.kilobytes)). "
                    + "\(RuntimeWords.whatHappens(self.runtime))")
                .foregroundStyle(.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "Runs")
                Text(self.runtime.removalCommand)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
            }
            if let error = runtimes.removal.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if self.runtimes.removal.isRemoving {
                    ProgressView().controlSize(.small)
                    Text("Removing…").foregroundStyle(.muted)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    self.runtimes.removal.clearError()
                    self.dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Remove Runtime", role: .destructive) {
                    Task { await self.runtimes.remove(self.runtime) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(self.runtimes.removal.isRemoving)
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(self.runtimes.removal.isRemoving)
    }
}

enum RuntimeWords {
    /// "144 days unused, no simulators": the flag, short enough for a badge.
    static func badge(_ runtime: SimulatorRuntime, staleDays: Int) -> String {
        var parts: [String] = []
        if let days = runtime.daysSinceUsed, days >= staleDays { parts.append("\(days) days unused") }
        if runtime.simulatorCount == 0 { parts.append("no simulators") }
        return parts.joined(separator: ", ")
    }

    /// Why it is flagged, or how it is used.
    static func usage(_ runtime: SimulatorRuntime, staleDays: Int) -> String {
        var sentence: String
        if let day = runtime.lastUsedDay {
            sentence = "Last used on \(day)"
            if let days = runtime.daysSinceUsed, days > 0 {
                sentence += days == 1 ? ", 1 day ago" : ", \(days) days ago"
            }
        } else {
            sentence = "Never used"
        }
        switch runtime.simulatorCount {
        case 0: sentence += ", and no simulator uses it any more."
        case 1: sentence += ". 1 simulator uses it."
        default: sentence += ". \(runtime.simulatorCount) simulators use it."
        }
        return sentence
    }

    static func whatHappens(_ runtime: SimulatorRuntime) -> String {
        var text = "The runtime is removed through Xcode's own tool, after you confirm. "
            + "Any simulator for \(runtime.platform) \(runtime.version) you create later downloads it again from "
            + "Xcode, Settings, Components."
        if runtime.simulatorCount > 0 {
            text += runtime.simulatorCount == 1
                ? " The simulator that uses it stops working until then."
                : " The \(runtime.simulatorCount) simulators that use it stop working until then."
        }
        return text
    }
}

enum XcodeWords {
    static func note(_ xcode: InstalledXcode, installedCount: Int) -> String {
        var text = "\(ProductInfo.name) never removes an Xcode. To remove one you no longer need, quit it and move "
            + "it to the Trash."
        if installedCount > 1 {
            text += " Each Xcode keeps its own compilation cache in DerivedData, so one you remove stops adding to it."
        }
        if xcode.isSelected {
            text += " This is the one xcode-select points at, which command line tools use."
        }
        return text
    }
}
