import DevSweepKit
import SwiftUI

// The Xcode versions screen. DevSweep never removes an Xcode; it can only
// reveal one in Finder.

struct XcodeVersionsView: View {
    var body: some View {
        ScrollView { XcodesContent() }
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

struct ArchivesNote: View {
    var body: some View {
        Text("Xcode Archives are never listed: their dSYMs symbolicate crash reports.")
            .font(.callout)
            .foregroundStyle(.muted)
    }
}

struct XcodesCard: View {
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
