import DevCleanKit
import SwiftUI

// The Android Studio screens: its installs, the SDK and emulators, and
// Gradle's shared caches. Listed for a look; devclean removes none of it.

struct AndroidStudiosView: View {
    var body: some View {
        ScrollView { AndroidStudiosContent() }
    }
}

struct AndroidSDKView: View {
    var body: some View {
        ScrollView { AndroidSDKContent() }
    }
}

struct GradleCachesView: View {
    var body: some View {
        ScrollView { GradleCachesContent() }
    }
}

struct AndroidStudiosContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AndroidScreen {
            AndroidCard(title: "Android Studio", note: "", entries: model.android?.studios ?? [],
                        empty: "No Android Studio found in the applications folders.")
        }
    }
}

struct AndroidSDKContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let android = model.android
        AndroidScreen {
            AndroidCard(title: "Emulators", note: "flagged after \(model.staleDays) days unchanged", entries: android?.emulators ?? [],
                        empty: "No emulators in ~/.android/avd.")
            AndroidCard(title: "System images", note: "flagged after \(model.staleDays) days without an emulator run",
                        entries: android?.systemImages ?? [], empty: "No system images in the SDK.")
            AndroidCard(title: "Platforms", note: "", entries: android?.platforms ?? [], empty: "No platforms in the SDK.")
            AndroidCard(title: "Build tools", note: "", entries: android?.buildTools ?? [], empty: "No build tools in the SDK.")
            AndroidCard(title: "Everything else in the SDK", note: "", entries: android?.otherSDKParts ?? [],
                        empty: android?.sdk == nil ? "No SDK in ~/Library/Android/sdk." : "Nothing else.")
        }
    }
}

struct GradleCachesContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AndroidScreen {
            AndroidCard(title: "~/.gradle", note: "shared by every Gradle project", entries: model.android?.gradleCaches ?? [],
                        empty: "No Gradle caches in ~/.gradle.")
        }
    }
}

/// The cards of an Android screen, and the promise under them.
private struct AndroidScreen<Cards: View>: View {
    @ViewBuilder let cards: Cards

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            cards
            Text("devclean only lists these. Remove them from Android Studio, or in Finder.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
}

private struct AndroidCard: View {
    @Environment(AppModel.self) private var model
    let title: String
    let note: String
    let entries: [AndroidEntry]
    let empty: String

    var body: some View {
        ExtrasCard(title: title, note: note, rowCount: entries.count) {
            if entries.isEmpty {
                EmptyExtrasRow(text: model.isLoadingAndroid && model.android == nil ? "Listing…" : empty)
            } else {
                let largest = Double(entries.map(\.kilobytes).max() ?? 1)
                ForEach(entries) { entry in
                    Divider().opacity(0.6)
                    AndroidRow(entry: entry, largest: largest)
                }
            }
        }
    }
}

private struct AndroidRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.extrasColumns) private var columns
    let entry: AndroidEntry
    let largest: Double

    var body: some View {
        let flagged = entry.flagReason(staleDays: model.staleDays) != nil
        let selected = model.currentAndroidEntry?.path == entry.path
        let tint: Color = flagged ? .orange : .secondary.opacity(0.6)
        HStack(spacing: 12) {
            Dot(color: tint)
            // The detail or badge gives way first, then the title truncates.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.title).fontWeight(.medium).lineLimit(1).layoutPriority(2)
                if flagged, let days = entry.daysUnused() {
                    Badge(text: "\(days) days unused", color: .orange)
                } else if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if columns.showsDate {
                Text(AndroidWords.lastUse(entry) ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)
            }
            if columns.showsBar {
                ThinBar(fraction: Double(entry.kilobytes) / max(largest, 1), color: tint)
                    .frame(width: 100)
            }
            Text(SizeText.of(kilobytes: entry.kilobytes))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
            if columns == .compact {
                Button("Reveal in Finder", systemImage: "folder") { model.revealInFinder([entry.path]) }
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                    .help("Reveal in Finder")
            } else {
                Button("Reveal in Finder") { model.revealInFinder([entry.path]) }
                    .controlSize(.small)
                    .frame(width: 118)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .tableRowSelection(selected)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedAndroidEntry = entry.path }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title), \(SizeText.of(kilobytes: entry.kilobytes))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Inspector

struct AndroidInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let entry = model.currentAndroidEntry {
            // Scrolls, so the column never asks the window for the height of its text.
            ScrollView {
                AndroidDetails(entry: entry)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Reveal in Finder") { model.revealInFinder([entry.path]) }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(18)
            }
        } else {
            ContentUnavailableView("Nothing here", systemImage: "shippingbox",
                                   description: Text(model.isLoadingAndroid ? "Listing…" : "Android Studio keeps nothing here."))
        }
    }
}

/// What the inspector says about one Android entry.
struct AndroidDetails: View {
    @Environment(AppModel.self) private var model
    let entry: AndroidEntry

    var body: some View {
        let reason = entry.flagReason(staleDays: model.staleDays)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Dot(color: reason == nil ? .secondary.opacity(0.6) : .orange)
                Eyebrow(text: AndroidWords.kind(entry.kind))
            }
            Text(entry.title).font(.title3.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(SizeText.of(kilobytes: entry.kilobytes))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                Text(reason == nil ? AndroidWords.state(entry) : "looks unused")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(reason == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            }
            section("Where") {
                Text(model.tilde(entry.path))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                if !entry.detail.isEmpty, entry.kind != .gradleCache {
                    Text(entry.detail)
                }
            }
            if let usage = AndroidWords.usage(entry, staleDays: model.staleDays) {
                section(reason == nil ? "Usage" : "Why it is flagged") { Text(usage) }
            }
            section("To remove it") { Text(AndroidWords.removal(entry.kind)) }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Eyebrow(text: title)
            content()
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The words the Android screens use.
enum AndroidWords {
    static func kind(_ kind: AndroidEntry.Kind) -> String {
        switch kind {
        case .studio: "Android Studio"
        case .systemImage: "System image"
        case .platform: "SDK platform"
        case .buildTools: "Build tools"
        case .sdkPart: "SDK"
        case .emulator: "Emulator"
        case .gradleCache: "Gradle cache"
        }
    }

    static func state(_ entry: AndroidEntry) -> String {
        switch entry.kind {
        case .studio: "installed"
        case .systemImage, .emulator: "in use"
        default: "on disk"
        }
    }

    /// "used 2026-10-20" for what is flagged by date, "opened ..." for an install.
    static func lastUse(_ entry: AndroidEntry) -> String? {
        switch entry.kind {
        case .studio: entry.lastUsed.map { "opened \(DayFormat.utc($0))" } ?? "last opened unknown"
        case .systemImage, .emulator: entry.lastUsed.map { "used \(DayFormat.utc($0))" }
        default: nil
        }
    }

    static func usage(_ entry: AndroidEntry, staleDays: Int) -> String? {
        switch entry.kind {
        case .emulator:
            guard let days = entry.daysUnused(), let used = entry.lastUsed else { return nil }
            return "Its disk images last changed \(DayFormat.utc(used)), \(days == 1 ? "1 day" : "\(days) days") ago. "
                + "Running an emulator changes them, so it is flagged after \(staleDays) days."
        case .systemImage:
            let count = entry.emulatorCount ?? 0
            let emulators = count == 0 ? "No emulator runs on it." : count == 1 ? "1 emulator runs on it." : "\(count) emulators run on it."
            guard let days = entry.daysUnused() else { return emulators }
            return "\(emulators) It or an emulator on it last changed \(days == 1 ? "1 day" : "\(days) days") ago; "
                + "it is flagged after \(staleDays) days."
        case .studio:
            return entry.lastUsed.map { "Last opened \(DayFormat.utc($0))." } ?? "Spotlight doesn't know when it was last opened."
        default:
            return nil
        }
    }

    static func removal(_ kind: AndroidEntry.Kind) -> String {
        switch kind {
        case .studio:
            "Move the app to the Trash. Its settings and caches in your Library stay until you remove them."
        case .systemImage, .platform, .buildTools, .sdkPart:
            "In Android Studio, Settings > Languages & Frameworks > Android SDK: uncheck it and apply. Projects that need it download it again."
        case .emulator:
            "In Android Studio's Device Manager, choose Delete from the emulator's menu. Its apps and data go with it."
        case .gradleCache:
            "Quit Android Studio and run ./gradlew --stop first. Gradle downloads or rebuilds what it needs on the next build, which is slower."
        }
    }
}
