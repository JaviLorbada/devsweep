import DevSweepKit
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
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let row: AppModel.Row
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
            if let breakdown = row.shownResult?.derivedData, row.wasMeasured || row.showsPrevious,
               !(row.shownResult?.isEmpty ?? true) || self.model.lastPartsClean != nil
            {
                DerivedDataParts(
                    breakdown: breakdown,
                    color: Palette.color(item),
                    selectable: self.row.result != nil && [.measured, .cleaning].contains(self.row.state))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, WindowLayout.inspectorTopPadding)
        .padding(.bottom, 20)
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

    private func location(_ row: AppModel.Row) -> some View {
        let paths = row.shownResult?.paths ?? []
        return VStack(alignment: .leading, spacing: 5) {
            Eyebrow(text: "Where")
            Text(row.shownResult?.location ?? "")
                .font(.caption.monospaced())
                .foregroundStyle(.muted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if paths.count > 1 {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(self.showsAllPaths ? paths : Array(paths.prefix(Self.pathsShown)), id: \.self) { path in
                        Text(self.model.tilde(path))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(self.model.tilde(path))
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
                Button("Reveal in Finder") { self.model.revealInFinder(paths) }
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
        case .cleaning: SizeText.of(kilobytes: row.leftKilobytes)
        case .cleaned: SizeText.of(kilobytes: row.kilobytes)
        }
    }

    private func stateWord(_ row: AppModel.Row) -> String {
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

extension DerivedDataPart {
    /// What a sentence calls it: a project by its folder, "the compilation cache".
    func name(in breakdown: DerivedDataBreakdown) -> String {
        switch self {
        case .compilationCache: "the compilation cache"
        case .moduleCache: "the module cache"
        case let .project(folder):
            breakdown.projects.first { $0.folder == folder }.map(DerivedDataParts.displayName)
                ?? URL(fileURLWithPath: folder).lastPathComponent
        case .other: "the rest of DerivedData"
        }
    }
}

/// The DerivedData breakdown: shared caches, then projects with their last
/// build. Each part can be ticked to clean on its own; the five largest
/// projects show, and the rest open to show each.
struct DerivedDataParts: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let breakdown: DerivedDataBreakdown
    let color: Color
    /// Whether parts can be ticked: this scan's breakdown, not the last one's.
    var selectable = false
    /// Whether every project shows, rather than the five largest and the rest summed.
    @State private var showsAllProjects = false

    static let projectsShown = 5

    struct Part: Identifiable {
        let id: String
        let name: String
        let status: String
        let gone: Bool
        let kilobytes: Int64
        /// The full workspace path, for a project.
        var path: String?
        /// What ticking it cleans; nil for the projects summed in one line.
        var part: DerivedDataPart?
    }

    var parts: [Part] {
        var parts: [Part] = []
        if self.breakdown.compilationCacheKilobytes > 0 {
            parts.append(Part(
                id: "compilation",
                name: "Shared compilation cache",
                status: "",
                gone: false,
                kilobytes: self.breakdown.compilationCacheKilobytes,
                part: .compilationCache))
        }
        if self.breakdown.moduleCacheKilobytes > 0 {
            parts.append(Part(
                id: "module",
                name: "Shared module cache",
                status: "",
                gone: false,
                kilobytes: self.breakdown.moduleCacheKilobytes,
                part: .moduleCache))
        }
        let shown = self.showsAllProjects ? self.breakdown.projects[...] : self.breakdown.projects
            .prefix(Self.projectsShown)
        for project in shown {
            let status = switch project.status {
            case let .built(day): "built \(day)"
            case .gone: "project gone"
            }
            parts.append(Part(
                id: project.folder,
                name: Self.displayName(project),
                status: status,
                gone: project.status == .gone,
                kilobytes: project.kilobytes,
                path: project.workspacePath,
                part: .project(project.folder)))
        }
        let rest = self.breakdown.projects.dropFirst(shown.count)
        if !rest.isEmpty {
            parts.append(Part(
                id: "rest",
                name: rest.count == 1 ? "1 more project" : "\(rest.count) more projects",
                status: "",
                gone: false,
                kilobytes: rest.reduce(0) { $0 + $1.kilobytes }))
        }
        if self.breakdown.otherKilobytes > 0 {
            parts.append(Part(
                id: "other",
                name: "Other",
                status: "",
                gone: false,
                kilobytes: self.breakdown.otherKilobytes,
                part: .other))
        }
        return parts.sorted { $0.kilobytes > $1.kilobytes }
    }

    /// The folder the project lives in, "atlas-2" for `.../atlas-2/Atlas.xcodeproj`:
    /// what tells apart copies of one project, and what you see in Finder.
    /// The project's own name when it sits at the top of the disk.
    nonisolated static func displayName(_ project: DerivedDataProject) -> String {
        guard let slash = project.name.lastIndex(of: "/") else { return project.name }
        let folder = project.name[..<slash]
        return folder.isEmpty ? String(project.name[project.name.index(after: slash)...]) : String(folder)
    }

    /// Room for a checkbox and the space after it, which the bars start past.
    private static let checkboxWidth: CGFloat = 22

    var body: some View {
        let parts = parts
        let largest = Double(max(parts.first?.kilobytes ?? 1, 1))
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Inside")
            if self.selectable, let clean = self.model.lastPartsClean {
                self.lastClean(clean)
            }
            ForEach(parts) { part in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if self.selectable { self.checkbox(part) }
                        if part.part == nil {
                            self.showAll(part)
                        } else {
                            Text(part.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(part.path.map(self.model.tilde) ?? "")
                        }
                        Spacer(minLength: 4)
                        Text(part.status)
                            .font(.caption)
                            .foregroundStyle(part.gone
                                ? AnyShapeStyle(Palette.text(.orange, dark: self.colorScheme == .dark))
                                : AnyShapeStyle(.muted))
                            .lineLimit(1)
                        Text(SizeText.of(kilobytes: part.kilobytes))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                    .font(.callout)
                    ThinBar(fraction: Double(part.kilobytes) / largest, color: self.color, height: 3)
                        .padding(.leading, self.selectable ? Self.checkboxWidth : 0)
                }
                .padding(.vertical, 4)
            }
            if self.showsAllProjects {
                Button("Show fewer projects") { self.toggleAllProjects() }
                    .buttonStyle(.link)
                    .font(.caption2)
            }
            Text("Each part comes back as you build; projects you no longer build stay gone.")
                .font(.caption)
                .foregroundStyle(.muted)
        }
    }

    @ViewBuilder
    private func checkbox(_ part: Part) -> some View {
        if let cleanable = part.part {
            Toggle("Mark \(part.name) for cleaning", isOn: Binding(
                get: { self.model.markedParts.contains(cleanable) },
                set: { self.model.setMarked(cleanable, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(self.model.isCleaning || self.model.isScanning)
                .frame(width: Self.checkboxWidth - 8, alignment: .leading)
        } else {
            Color.clear.frame(width: Self.checkboxWidth - 8)
        }
    }

    /// "7 more projects ›", which opens to show each.
    private func showAll(_ part: Part) -> some View {
        Button { self.toggleAllProjects() } label: {
            HStack(spacing: 4) {
                Text(part.name).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show each project, to clean it on its own")
    }

    private func toggleAllProjects() {
        withAnimation(Motion.animation(.easeInOut(duration: 0.25))) { self.showsAllProjects.toggle() }
    }

    /// "Moved 2 projects to the Trash, 25.2 GB. Put Back"
    private func lastClean(_ clean: AppModel.PartsClean) -> some View {
        let size = SizeText.of(kilobytes: clean.kilobytes)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(clean
                .canPutBack ? "Moved \(clean.summary) to the Trash, \(size)." : "Deleted \(clean.summary), \(size).")
                .foregroundStyle(.muted)
            if clean.canPutBack {
                Button("Put Back") { Task { await self.model.putBackParts() } }
                    .buttonStyle(.link)
                    .disabled(self.model.isCleaning)
            }
        }
        .font(.caption)
    }
}

/// The inspector's bottom button: Clean, Put back, or a disabled Measuring.
struct InspectorAction: View {
    @Environment(AppModel.self) private var model
    let row: AppModel.Row

    var body: some View {
        switch self.row.state {
        case .waiting, .measuring:
            self.wide(Button("Measuring") {}.buttonStyle(.prominentAction).disabled(true))
        case .measured where self.row.isLive && self.row.item == .derivedData && !self.model.markedParts.isEmpty:
            let parts = "\(AppModel.summary(of: self.model.markedParts)), "
                + SizeText.of(kilobytes: self.model.markedPartsKilobytes)
            self.wide(Button("Clean \(parts)") {
                Task { await self.model.requestCleanParts() }
            }
            .buttonStyle(.prominentAction)
            .disabled(self.model.isScanning || self.model.isCleaning))
        case .measured where self.row.isLive:
            self.wide(Button("Clean \(self.row.item.shortName)") {
                Task { await self.model.requestClean([self.row.item]) }
            }
            .buttonStyle(.prominentAction)
            .disabled(self.model.isScanning || self.model.isCleaning))
        case .cleaning:
            self.wide(Button("Cleaning") {}.buttonStyle(.glass).disabled(true))
        case .cleaned where self.row.canPutBack:
            self.wide(Button("Put Back") {
                Task { await self.model.putBack(self.row.item) }
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
