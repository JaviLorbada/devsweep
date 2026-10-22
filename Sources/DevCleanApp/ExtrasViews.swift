import DevCleanKit
import SwiftUI

// The screens for things devclean lists but never deletes on its own:
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
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExtrasCard(title: "Runtimes", note: "flagged after \(model.staleDays) days unused or with no simulators",
                       rowCount: model.extras?.runtimes.count ?? 0) {
                if let runtimes = model.extras?.runtimes, !runtimes.isEmpty {
                    let largest = Double(runtimes.map(\.kilobytes).max() ?? 1)
                    ForEach(runtimes) { runtime in
                        Divider().opacity(0.6)
                        RuntimeRow(runtime: runtime, largest: largest)
                    }
                } else {
                    EmptyExtrasRow(text: model.isLoadingExtras ? "Listing runtimes…" : "No simulator runtimes found.")
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
            .foregroundStyle(.secondary)
    }
}

private struct XcodesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let xcodes = model.extras?.xcodes ?? []
        ExtrasCard(title: "Xcode versions", note: xcodes.count > 1 ? "each keeps its own compilation cache in DerivedData" : "",
                   rowCount: xcodes.count) {
            if xcodes.isEmpty {
                EmptyExtrasRow(text: model.isLoadingExtras ? "Listing Xcodes…" : "No Xcode found in the applications folders.")
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
private struct ExtrasCard<Rows: View>: View {
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
                    Text(title).fontWeight(.semibold).lineLimit(1).layoutPriority(1)
                    Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
                rows
            }
            .environment(\.extrasColumns, ExtrasColumns(width: proxy.size.width))
        }
        .frame(height: 34 + CGFloat(max(rowCount, 1)) * 41)
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

    var showsBar: Bool { self == .full }
    var showsDate: Bool { self != .compact }
}

extension EnvironmentValues {
    @Entry var extrasColumns = ExtrasColumns.compact
}

private struct EmptyExtrasRow: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.6)
            Text(text)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 40)
        }
    }
}

private struct RuntimeRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.extrasColumns) private var columns
    let runtime: SimulatorRuntime
    let largest: Double

    var body: some View {
        let reason = runtime.flagReason(staleDays: model.staleDays)
        let selected = model.screen == .simulatorRuntimes && model.currentRuntime?.id == runtime.id
        let tint: Color = reason == nil ? .secondary.opacity(0.6) : .orange
        HStack(spacing: 12) {
            Dot(color: tint)
            // Everything here can shrink: the badge or count gives way first,
            // then the title truncates.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(runtime.title).fontWeight(.medium).lineLimit(1).layoutPriority(2)
                if let reason {
                    Badge(text: RuntimeWords.badge(runtime, staleDays: model.staleDays), color: .orange)
                        .help(reason)
                } else {
                    Text(runtime.simulatorCount == 1 ? "1 simulator" : "\(runtime.simulatorCount) simulators")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if columns.showsDate {
                Text(runtime.lastUsedDay.map { "used \($0)" } ?? "never used")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)
            }
            if columns.showsBar {
                ThinBar(fraction: Double(runtime.kilobytes) / max(largest, 1), color: tint)
                    .frame(width: 100)
            }
            Text(SizeText.of(kilobytes: runtime.kilobytes))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
            Group {
                if reason == nil {
                    Color.clear
                } else if columns == .compact {
                    Button("Remove Runtime", systemImage: "trash") {
                        model.selectedRuntime = runtime.id
                        model.runtimeToRemove = runtime
                    }
                    .labelStyle(.iconOnly)
                    .help("Remove Runtime")
                } else {
                    Button("Remove Runtime") {
                        model.selectedRuntime = runtime.id
                        model.runtimeToRemove = runtime
                    }
                }
            }
            .controlSize(.small)
            .frame(width: columns == .compact ? 28 : 118)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(selected ? Color.accentColor.opacity(0.14) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedRuntime = runtime.id }
    }
}

private struct XcodeRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.extrasColumns) private var columns
    let xcode: InstalledXcode
    let largest: Double

    var body: some View {
        let selected = model.screen == .xcodeVersions && model.currentXcode?.path == xcode.path
        HStack(spacing: 12) {
            Dot(color: .secondary.opacity(0.6))
            // Everything here can shrink: the path gives way first, then the
            // title truncates. Nothing in a row may insist on its full width.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(xcode.title).fontWeight(.medium).lineLimit(1).layoutPriority(2)
                if xcode.isSelected { Badge(text: "selected", color: .accentColor).layoutPriority(2) }
                if columns != .compact {
                    Text(model.tilde(xcode.path))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if columns.showsDate {
                Text(xcode.lastOpened.map { "opened \(DayFormat.utc($0))" } ?? "last opened unknown")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)
            }
            if columns.showsBar {
                ThinBar(fraction: Double(xcode.kilobytes) / max(largest, 1), color: .secondary.opacity(0.6))
                    .frame(width: 100)
            }
            Text(SizeText.of(kilobytes: xcode.kilobytes))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
            if columns == .compact {
                Button("Reveal in Finder", systemImage: "folder") { model.revealInFinder([xcode.path]) }
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                    .help("Reveal in Finder")
            } else {
                Button("Reveal in Finder") { model.revealInFinder([xcode.path]) }
                    .controlSize(.small)
                    .frame(width: 118)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(selected ? Color.accentColor.opacity(0.14) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedXcode = xcode.path
        }
    }
}

// MARK: Inspectors

struct RuntimeInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let runtime = model.currentRuntime {
            // Scrolls, so the column never asks the window for the height of
            // its text: at a small width that would be thousands of points.
            ScrollView {
                RuntimeDetails(runtime: runtime)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Remove Runtime") { model.runtimeToRemove = runtime }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(18)
            }
        } else {
            ContentUnavailableView("No runtime", systemImage: "iphone",
                                   description: Text(model.isLoadingExtras ? "Listing runtimes…" : "No simulator runtimes found."))
        }
    }
}

/// What the inspector says about one runtime.
struct RuntimeDetails: View {
    @Environment(AppModel.self) private var model
    let runtime: SimulatorRuntime

    var body: some View {
        let reason = runtime.flagReason(staleDays: model.staleDays)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Dot(color: reason == nil ? .secondary.opacity(0.6) : .orange)
                Eyebrow(text: "Simulator runtime")
            }
            Text(runtime.title).font(.title3.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(SizeText.of(kilobytes: runtime.kilobytes))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                Text(reason == nil ? "in use" : "looks unused")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(reason == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            }
            Section(reason == nil ? "Usage" : "Why it is flagged") {
                Text(RuntimeWords.usage(runtime, staleDays: model.staleDays))
            }
            Section("What happens") {
                Text(RuntimeWords.whatHappens(runtime))
            }
            Section("Runs") {
                Text(runtime.removalCommand)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
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
                Eyebrow(text: title)
                content
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct XcodeInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let xcode = model.currentXcode {
            // Scrolls, so the column never asks the window for the height of
            // its text: at a small width that would be thousands of points.
            ScrollView {
                XcodeDetails(xcode: xcode, installedCount: model.extras?.xcodes.count ?? 0)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Reveal in Finder") { model.revealInFinder([xcode.path]) }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(18)
            }
        } else {
            ContentUnavailableView("No Xcode", systemImage: "hammer",
                                   description: Text(model.isLoadingExtras ? "Listing Xcodes…" : "No Xcode found in the applications folders."))
        }
    }
}

/// What the inspector says about one Xcode.
struct XcodeDetails: View {
    @Environment(AppModel.self) private var model
    let xcode: InstalledXcode
    let installedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Dot(color: .secondary.opacity(0.6))
                Eyebrow(text: "Xcode")
            }
            Text(xcode.title).font(.title3.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(SizeText.of(kilobytes: xcode.kilobytes))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                Text(xcode.isSelected ? "selected" : "installed")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "Where")
                Text(model.tilde(xcode.path))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(xcode.lastOpened.map { "Last opened \(DayFormat.utc($0))." } ?? "Spotlight doesn't know when it was last opened.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "What happens")
                Text(XcodeWords.note(xcode, installedCount: installedCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: Removing a runtime

/// The confirmation before removing a runtime, showing the exact command.
struct RemoveRuntimeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let runtime: SimulatorRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remove \(runtime.title)?")
                .font(.title3.weight(.semibold))
            Text("This frees \(SizeText.of(kilobytes: runtime.kilobytes)). \(RuntimeWords.whatHappens(runtime))")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "Runs")
                Text(runtime.removalCommand)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
            }
            if let error = model.runtimeRemovalError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if model.isRemovingRuntime {
                    ProgressView().controlSize(.small)
                    Text("Removing…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    model.runtimeRemovalError = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Remove Runtime", role: .destructive) {
                    Task { await model.removeRuntime(runtime) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isRemovingRuntime)
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(model.isRemovingRuntime)
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
            + "Any simulator for \(runtime.platform) \(runtime.version) you create later downloads it again from Xcode, Settings, Components."
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
        var text = "devclean never removes an Xcode. To remove one you no longer need, quit it and move it to the Trash."
        if installedCount > 1 {
            text += " Each Xcode keeps its own compilation cache in DerivedData, so one you remove stops adding to it."
        }
        if xcode.isSelected {
            text += " This is the one xcode-select points at, which command line tools use."
        }
        return text
    }
}
