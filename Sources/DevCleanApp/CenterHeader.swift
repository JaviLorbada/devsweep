import SwiftUI

/// The center panel's top row: the screen's title and status on the left, and
/// on the right what acts on the scan, its progress, Ring or Blocks, and Scan
/// Again or Stop.
///
/// Sized from the width it is given, like the footer, so the controls drop
/// their words instead of asking the column for more room.
struct CenterHeader: View {
    @Environment(AppModel.self) private var model
    let title: String

    static let height: CGFloat = 56

    /// What the controls show at a given width of the center panel.
    struct Fit: Equatable {
        /// "Measuring DerivedData" next to the progress bar.
        var capsuleText: Bool
        /// "Ring" and "Blocks" rather than their icons.
        var pickerText: Bool

        init(width: CGFloat) {
            capsuleText = width >= 680
            pickerText = width >= 560
        }
    }

    var body: some View {
        GeometryReader { proxy in
            row(fit: Fit(width: proxy.size.width))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: Self.height)
    }

    private func row(fit: Fit) -> some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(model.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if model.isScanning {
                    ScanCapsule(showsText: fit.capsuleText)
                }
                if model.screen == .overview {
                    // Two pickers rather than a condition inside one: a
                    // segmented picker shows every branch it finds.
                    if fit.pickerText {
                        Picker("Chart", selection: $model.chartStyle) {
                            ForEach(AppModel.ChartStyle.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .help("Show sizes as a ring or as blocks")
                    } else {
                        Picker("Chart", selection: $model.chartStyle) {
                            ForEach(AppModel.ChartStyle.allCases) { Image(systemName: $0.systemImage).accessibilityLabel($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .help("Show sizes as a ring or as blocks")
                    }
                }
                Button(model.isScanning ? "Stop" : "Scan Again") {
                    model.isScanning ? model.stopScan() : model.scan()
                }
                .disabled(model.engine == nil)
            }
            .fixedSize()
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }
}

/// "Measuring DerivedData" with a thin bar for how many items are done.
struct ScanCapsule: View {
    @Environment(AppModel.self) private var model
    var showsText = true

    var body: some View {
        HStack(spacing: 10) {
            if showsText {
                Text(capsuleText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .leading)
            }
            ProgressView(value: model.scanProgress)
                .progressViewStyle(.linear)
                .frame(width: 64)
                .animation(.easeInOut(duration: 0.3), value: model.scanProgress)
        }
        .padding(.horizontal, 6)
        .help(capsuleText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(capsuleText)
        .accessibilityValue("\(Int(model.scanProgress * 100)) percent")
    }

    /// "Measuring DerivedData", "Measuring DerivedData and 2 more".
    var capsuleText: String {
        let measuring = model.measuringItems
        guard let first = measuring.last else { return "Listing Xcodes and runtimes" }
        return measuring.count == 1 ? "Measuring \(first.shortName)" : "Measuring \(first.shortName) and \(measuring.count - 1) more"
    }
}

extension AppModel.ChartStyle {
    var systemImage: String {
        switch self {
        case .ring: "chart.pie"
        case .blocks: "square.grid.2x2"
        }
    }
}
