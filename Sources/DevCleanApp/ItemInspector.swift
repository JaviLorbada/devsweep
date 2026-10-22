import DevCleanKit
import SwiftUI

/// The selected item: what it is, where it lives, what cleaning it does, and
/// for DerivedData what is inside.
struct ItemInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let item = model.selection, let row = model.rows[item] {
            ScrollView {
                // A fresh one per item, so a list expanded for one item
                // starts short for the next.
                ItemDetails(row: row)
                    .id(item)
            }
            .safeAreaInset(edge: .bottom) {
                InspectorAction(row: row)
                    .padding(18)
            }
        } else {
            ContentUnavailableView("Nothing selected", systemImage: "sidebar.trailing",
                                   description: Text("Select an item to see what it holds."))
        }
    }
}

/// Everything the inspector says about one item.
struct ItemDetails: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let row: AppModel.Row
    /// Whether the Where list shows every path rather than the first few.
    @State private var showsAllPaths = false

    static let pathsShown = 8

    var body: some View {
        let item = row.item
        VStack(alignment: .leading, spacing: 14) {
            header(row)
            location(row)
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "What happens")
                Text(item.whatHappens)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let breakdown = row.shownResult?.derivedData, row.wasMeasured || row.showsPrevious, !(row.shownResult?.isEmpty ?? true) {
                DerivedDataParts(breakdown: breakdown, color: Palette.color(item))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ row: AppModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Dot(color: Palette.color(row.item.family))
                Eyebrow(text: row.item.family.name)
            }
            Text(row.shownResult?.label ?? row.item.name)
                .font(.title3.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(heroSize(row))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(stateWord(row))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(row.state == .cleaned ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            }
        }
    }

    private func location(_ row: AppModel.Row) -> some View {
        let paths = row.shownResult?.paths ?? []
        return VStack(alignment: .leading, spacing: 5) {
            Eyebrow(text: "Where")
            Text(row.shownResult?.location ?? "")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if paths.count > 1 {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(showsAllPaths ? paths : Array(paths.prefix(Self.pathsShown)), id: \.self) { path in
                        Text(model.tilde(path))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(model.tilde(path))
                    }
                    if paths.count > Self.pathsShown {
                        Button(showsAllPaths ? "Show fewer" : "and \(paths.count - Self.pathsShown) more") {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showsAllPaths.toggle() }
                        }
                        .buttonStyle(.link)
                        .font(.caption2)
                        .accessibilityHint(showsAllPaths ? "Hides all but the first \(Self.pathsShown) paths" : "Shows every path")
                    }
                }
            }
            if !paths.isEmpty {
                Button("Reveal in Finder") { model.revealInFinder(paths) }
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
    }

    private func heroSize(_ row: AppModel.Row) -> String {
        switch row.state {
        case .waiting: row.showsPrevious ? SizeText.of(kilobytes: row.shownKilobytes) : "–"
        case .notMeasured: "–"
        case .measuring: SizeText.of(bytes: row.progressBytes)
        case .measured: !row.sizeKnown && row.kilobytes == 0 ? "?" : SizeText.of(kilobytes: row.kilobytes)
        case .cleaning, .cleaned: SizeText.of(kilobytes: row.kilobytes)
        }
    }

    private func stateWord(_ row: AppModel.Row) -> String {
        switch row.state {
        case .waiting: row.showsPrevious ? "last scan, waiting" : "waiting"
        case .measuring: "measuring"
        case .notMeasured: "not measured"
        case .cleaning: "cleaning"
        case .cleaned: row.canPutBack ? "in Trash" : "deleted"
        case .measured:
            if !row.sizeKnown { "size unknown" }
            else if row.result?.isEmpty ?? true { "nothing to clean" }
            else { "reclaimable" }
        }
    }
}

/// The DerivedData breakdown: shared caches, then projects with their last build.
struct DerivedDataParts: View {
    @Environment(AppModel.self) private var model
    let breakdown: DerivedDataBreakdown
    let color: Color

    struct Part: Identifiable {
        let id: String
        let name: String
        let status: String
        let gone: Bool
        let kilobytes: Int64
        /// The full workspace path, for a project.
        var path: String?
    }

    var parts: [Part] {
        var parts: [Part] = []
        if breakdown.compilationCacheKilobytes > 0 {
            parts.append(Part(id: "compilation", name: "Compilation cache, all projects", status: "", gone: false, kilobytes: breakdown.compilationCacheKilobytes))
        }
        if breakdown.moduleCacheKilobytes > 0 {
            parts.append(Part(id: "module", name: "Module cache, all projects", status: "", gone: false, kilobytes: breakdown.moduleCacheKilobytes))
        }
        for project in breakdown.projects.prefix(5) {
            let status: String = switch project.status {
            case .built(let day): "built \(day)"
            case .gone: ""
            }
            parts.append(Part(id: project.folder, name: Self.displayName(project), status: status,
                              gone: project.status == .gone, kilobytes: project.kilobytes, path: project.workspacePath))
        }
        let rest = breakdown.projects.dropFirst(5)
        if !rest.isEmpty {
            parts.append(Part(id: "rest", name: rest.count == 1 ? "1 more project" : "\(rest.count) more projects", status: "", gone: false,
                              kilobytes: rest.reduce(0) { $0 + $1.kilobytes }))
        }
        if breakdown.otherKilobytes > 0 {
            parts.append(Part(id: "other", name: "Other", status: "", gone: false, kilobytes: breakdown.otherKilobytes))
        }
        return parts.sorted { $0.kilobytes > $1.kilobytes }
    }

    /// The folder the project lives in, "kite-1" for `.../kite-1/Waypoint.xcodeproj`:
    /// what tells apart copies of one project, and what you see in Finder.
    /// The project's own name when it sits at the top of the disk.
    static func displayName(_ project: DerivedDataProject) -> String {
        guard let slash = project.name.lastIndex(of: "/") else { return project.name }
        let folder = project.name[..<slash]
        return folder.isEmpty ? String(project.name[project.name.index(after: slash)...]) : String(folder)
    }

    var body: some View {
        let parts = parts
        let largest = Double(max(parts.first?.kilobytes ?? 1, 1))
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Inside")
            ForEach(parts) { part in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(part.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(part.path.map(model.tilde) ?? "")
                        if part.gone { Badge(text: "project gone", color: .orange) }
                        Spacer(minLength: 4)
                        Text(part.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(SizeText.of(kilobytes: part.kilobytes))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                    .font(.callout)
                    ThinBar(fraction: Double(part.kilobytes) / largest, color: color, height: 3)
                }
                .padding(.vertical, 4)
            }
            Text("Each part comes back as you build; projects you no longer build stay gone.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

/// The inspector's bottom button: Clean, Put back, or a disabled Measuring.
struct InspectorAction: View {
    @Environment(AppModel.self) private var model
    let row: AppModel.Row

    var body: some View {
        switch row.state {
        case .waiting, .measuring:
            wide(Button("Measuring") {}.buttonStyle(.glassProminent).disabled(true))
        case .measured where row.isLive:
            wide(Button("Clean \(row.item.shortName)") {
                Task { await model.requestClean([row.item]) }
            }
            .buttonStyle(.glassProminent)
            .disabled(model.isScanning || model.isCleaning))
        case .cleaning:
            wide(Button("Cleaning") {}.buttonStyle(.glass).disabled(true))
        case .cleaned where row.canPutBack:
            wide(Button("Put Back") {
                Task { await model.putBack(row.item) }
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
