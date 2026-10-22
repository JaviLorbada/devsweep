import DevCleanKit
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            OverviewContent()
        }
        .safeAreaInset(edge: .bottom) {
            OverviewFooter()
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .animation(.easeInOut(duration: 0.4), value: model.chartStyle)
    }
}

/// The chart card, the items and any notes from the scan.
struct OverviewContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Group {
                switch model.chartStyle {
                case .ring: RingChart()
                case .blocks: BlocksChart()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 280)
            .card()

            ItemsCard()

            if !model.warnings.isEmpty {
                WarningsNote(warnings: model.warnings)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
}

/// Things the scan skipped and why, in the script's words.
struct WarningsNote: View {
    let warnings: [String]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning).font(.caption).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Label(warnings.count == 1 ? "1 note from the scan" : "\(warnings.count) notes from the scan",
                  systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .card()
    }
}

/// The Trash toggle, what is marked, and the button that cleans it.
struct OverviewFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            bar(wide: proxy.size.width >= 640)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: 32)
    }

    private func bar(wide: Bool) -> some View {
        @Bindable var model = model
        return HStack(spacing: 14) {
            Toggle(wide ? "Move to Trash, so anything can be put back" : "Move to Trash", isOn: $model.moveToTrash)
                .toggleStyle(.checkbox)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help("Off deletes for good, after asking")
            Spacer(minLength: 0)
            Text(model.markedRows.isEmpty ? "Nothing marked" : "\(model.markedRows.count) marked, \(SizeText.of(kilobytes: model.markedKilobytes))")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.numericText())
            Button(model.markedRows.isEmpty ? "Clean marked" : "Clean \(SizeText.of(kilobytes: model.markedKilobytes))") {
                Task { await model.requestClean(model.markedRows.map(\.item)) }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.markedRows.isEmpty || model.isScanning || model.isCleaning)
            .layoutPriority(1)
        }
    }
}
