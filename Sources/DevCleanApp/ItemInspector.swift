import DevCleanKit
import SwiftUI

/// The selected item: what it is, where it lives, what cleaning it does, and
/// for DerivedData what is inside.
struct ItemInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let item = model.selection, let row = model.rows[item] {
            ScrollView {
                ItemDetails(row: row)
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
    let row: AppModel.Row

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
                    ForEach(paths.prefix(8), id: \.self) { path in
                        Text(model.tilde(path))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if paths.count > 8 {
                        Text("and \(paths.count - 8) more").font(.caption2).foregroundStyle(.tertiary)
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
    let breakdown: DerivedDataBreakdown
    let color: Color

    struct Part: Identifiable {
        let id: String
        let name: String
        let status: String
        let gone: Bool
        let kilobytes: Int64
    }

    var parts: [Part] {
        var parts: [Part] = []
        if breakdown.compilationCacheKilobytes > 0 {
            parts.append(Part(id: "compilation", name: "Compilation cache, all projects", status: "", gone: false, kilobytes: breakdown.compilationCacheKilobytes))
        }
        if breakdown.moduleCacheKilobytes > 0 {
            parts.append(Part(id: "module", name: "Module cache, all projects", status: "", gone: false, kilobytes: breakdown.moduleCacheKilobytes))
        }
        let shown = breakdown.projects.prefix(5)
        for project in shown {
            let status: String = switch project.status {
            case .built(let day): "built \(day)"
            case .gone: ""
            }
            parts.append(Part(id: project.folder, name: Self.displayName(project, among: Array(shown)), status: status,
                              gone: project.status == .gone, kilobytes: project.kilobytes))
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

    /// "Atlas" for "Atlas/Atlas"; "Waypoint (kite-1)" when several
    /// projects share a name in different folders.
    static func displayName(_ project: DerivedDataProject, among projects: [DerivedDataProject]) -> String {
        let (folder, name) = split(project.name)
        let shared = projects.filter { split($0.name).name == name }.count > 1
        return shared && folder != name ? "\(name) (\(folder))" : name
    }

    private static func split(_ name: String) -> (folder: String, name: String) {
        guard let slash = name.lastIndex(of: "/") else { return ("", name) }
        return (String(name[..<slash]), String(name[name.index(after: slash)...]))
    }

    var body: some View {
        let parts = parts
        let largest = Double(max(parts.first?.kilobytes ?? 1, 1))
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Inside")
            ForEach(parts) { part in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(part.name).lineLimit(1).truncationMode(.middle)
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
