import DevSweepKit
import SwiftUI

extension ItemPart {
    /// What the inspector's list calls it: a project, or a build folder, by
    /// the folder it belongs to.
    func listName(in result: ItemResult) -> String {
        switch self {
        case .compilationCache: "Shared compilation cache"
        case .moduleCache: "Shared module cache"
        case .other: "Other"
        case let .folder(path):
            result.derivedData?.projects.first { $0.folder == path }.map(DerivedDataParts.displayName)
                ?? URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
        }
    }

    /// What a sentence calls it, clear out of context: "DerivedData for
    /// Atlas", "the compilation cache", "kite-1/.build".
    func sentenceName(in result: ItemResult) -> String {
        switch self {
        case .compilationCache: "the compilation cache"
        case .moduleCache: "the module cache"
        case .other: "the rest of DerivedData"
        case let .folder(path):
            result.derivedData != nil
                ? "DerivedData for \(self.listName(in: result))"
                : "\(self.listName(in: result))/\(URL(fileURLWithPath: path).lastPathComponent)"
        }
    }
}

/// How the inspector names DerivedData's projects.
enum DerivedDataParts {
    /// The folder the project lives in, "atlas-2" for `.../atlas-2/Atlas.xcodeproj`:
    /// what tells apart copies of one project, and what you see in Finder.
    /// The project's own name when it sits at the top of the disk.
    nonisolated static func displayName(_ project: DerivedDataProject) -> String {
        guard let slash = project.name.lastIndex(of: "/") else { return project.name }
        let folder = project.name[..<slash]
        return folder.isEmpty ? String(project.name[project.name.index(after: slash)...]) : String(folder)
    }
}

/// An item's parts, largest first, each with a box to clean it on its own:
/// DerivedData's shared caches, projects with their last build, and the
/// rest; or a build item's folders, by the project each belongs to. Past
/// the five largest projects or folders, the rest open to show each.
struct PartsList: View {
    @Environment(ScanModel.self) private var scan
    @Environment(MarksModel.self) private var marks
    @Environment(CleaningModel.self) private var cleaning
    @Environment(\.colorScheme) private var colorScheme
    let result: ItemResult
    let color: Color
    /// Whether parts can be ticked: this scan's result, not the last one's.
    var selectable = false
    /// Whether every project or folder shows, rather than the five largest
    /// and the rest summed.
    @State private var showsAll = false

    static let shown = 5

    /// Whether the inspector lists the item's parts.
    static func lists(_ result: ItemResult) -> Bool {
        result.derivedData != nil || self.listsFolders(result)
    }

    /// Whether it lists a build item's folders, which the scan measured one by one.
    static func listsFolders(_ result: ItemResult) -> Bool {
        result.item.cleansByFolder && result.folderKilobytes != nil
    }

    struct Line: Identifiable {
        let id: String
        let name: String
        var status = ""
        var gone = false
        /// A second line, the folder's path, for a build item's folder.
        var detail: String?
        let kilobytes: Int64
        var help = ""
        /// What ticking it cleans; nil for the ones summed in one line.
        var part: ItemPart?
    }

    private var isDerivedData: Bool {
        self.result.derivedData != nil
    }

    var lines: [Line] {
        if let breakdown = result.derivedData { return self.lines(breakdown) }
        let folders = self.result.paths
            .map { (path: $0, kilobytes: self.result.folderKilobytes?[$0] ?? 0) }
            .sorted { $0.kilobytes > $1.kilobytes }
        let names = Self.folderNames(self.result.paths)
        let shown = self.showsAll ? folders[...] : folders.prefix(Self.shown)
        var lines = shown.map { folder in
            Line(
                id: folder.path,
                name: names[folder.path] ?? folder.path,
                detail: self.scan.tilde(folder.path),
                kilobytes: folder.kilobytes,
                help: self.scan.tilde(folder.path),
                part: .folder(folder.path))
        }
        let rest = folders.dropFirst(shown.count)
        if !rest.isEmpty {
            lines.append(Line(
                id: "rest",
                name: rest.count == 1 ? "1 more folder" : "\(rest.count) more folders",
                kilobytes: rest.reduce(0) { $0 + $1.kilobytes }))
        }
        return lines
    }

    private func lines(_ breakdown: DerivedDataBreakdown) -> [Line] {
        var lines: [Line] = []
        for part in [ItemPart.compilationCache, .moduleCache, .other] where breakdown.kilobytes(of: part) > 0 {
            lines.append(Line(
                id: part.listName(in: self.result),
                name: part.listName(in: self.result),
                kilobytes: breakdown.kilobytes(of: part),
                part: part))
        }
        let shown = self.showsAll ? breakdown.projects[...] : breakdown.projects.prefix(Self.shown)
        for project in shown {
            let status = switch project.status {
            case let .built(day): "built \(day)"
            case .gone: "project gone"
            }
            lines.append(Line(
                id: project.folder,
                name: DerivedDataParts.displayName(project),
                status: status,
                gone: project.status == .gone,
                kilobytes: project.kilobytes,
                help: self.scan.tilde(project.workspacePath),
                part: .folder(project.folder)))
        }
        let rest = breakdown.projects.dropFirst(shown.count)
        if !rest.isEmpty {
            lines.append(Line(
                id: "rest",
                name: rest.count == 1 ? "1 more project" : "\(rest.count) more projects",
                kilobytes: rest.reduce(0) { $0 + $1.kilobytes }))
        }
        return Self.ordered(lines)
    }

    /// Largest first, with the summed line, which opens to show the rest,
    /// last, where "Show fewer" takes its place once open.
    static func ordered(_ lines: [Line]) -> [Line] {
        let parts = lines.filter { $0.part != nil }.sorted { $0.kilobytes > $1.kilobytes }
        return parts + lines.filter { $0.part == nil }
    }

    /// Each folder by the folder it sits in, "kite-1" for
    /// `.../kite-1/.build`, and by the two above it where that name repeats.
    static func folderNames(_ paths: [String]) -> [String: String] {
        func parents(_ path: String, _ count: Int) -> String {
            path.split(separator: "/").dropLast().suffix(count).joined(separator: "/")
        }
        var names = Dictionary(uniqueKeysWithValues: paths.map { ($0, parents($0, 1)) })
        let repeated = Dictionary(grouping: names.values) { $0 }.filter { $0.value.count > 1 }
        for path in paths where repeated[names[path] ?? ""] != nil {
            names[path] = parents(path, 2)
        }
        return names
    }

    /// Room for a checkbox and the space after it, which the bars start past.
    private static let checkboxWidth: CGFloat = 22

    var body: some View {
        let lines = lines
        let largest = Double(max(lines.map(\.kilobytes).max() ?? 1, 1))
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: self.isDerivedData ? "Inside" : "Folders")
            if self.selectable, let clean = self.cleaning.lastPartsClean(of: self.result.item) {
                self.lastClean(clean)
            }
            ForEach(lines) { line in
                self.line(line, largest: largest)
            }
            if self.showsAll {
                Button(self.isDerivedData ? "Show fewer projects" : "Show fewer folders") { self.toggleAll() }
                    .buttonStyle(.link)
                    .font(.caption2)
            }
            if self.isDerivedData {
                Text("Each part comes back as you build; projects you no longer build stay gone.")
                    .font(.caption)
                    .foregroundStyle(.muted)
            }
        }
    }

    private func line(_ line: Line, largest: Double) -> some View {
        let indent = self.selectable ? Self.checkboxWidth : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if self.selectable { self.checkbox(line) }
                if line.part == nil {
                    self.showAll(line)
                } else {
                    Text(line.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(line.help)
                }
                Spacer(minLength: 4)
                Text(line.status)
                    .font(.caption)
                    .foregroundStyle(line.gone
                        ? AnyShapeStyle(Palette.text(.orange, dark: self.colorScheme == .dark))
                        : AnyShapeStyle(.muted))
                    .lineLimit(1)
                Text(SizeText.of(kilobytes: line.kilobytes))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
            .font(.callout)
            if let detail = line.detail {
                Text(detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, indent)
            }
            ThinBar(fraction: Double(line.kilobytes) / largest, color: self.color, height: 3)
                .padding(.leading, indent)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func checkbox(_ line: Line) -> some View {
        if let part = line.part {
            let item = self.result.item
            Toggle("Mark \(line.name) for cleaning", isOn: Binding(
                get: { self.marks.markedParts(of: item).contains(part) },
                set: { self.marks.setMarked(part, of: item, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(self.scan.isCleaning || self.scan.isScanning)
                .frame(width: Self.checkboxWidth - 8, alignment: .leading)
        } else {
            Color.clear.frame(width: Self.checkboxWidth - 8)
        }
    }

    /// "7 more projects ›", which opens to show each.
    private func showAll(_ line: Line) -> some View {
        Button { self.toggleAll() } label: {
            HStack(spacing: 4) {
                Text(line.name).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(self
            .isDerivedData ? "Show each project, to clean it on its own" : "Show each folder, to clean it on its own")
    }

    private func toggleAll() {
        withAnimation(Motion.animation(.easeInOut(duration: 0.25))) { self.showsAll.toggle() }
    }

    /// "Moved 2 projects to the Trash, 25.2 GB. Put Back"
    private func lastClean(_ clean: CleaningModel.PartsClean) -> some View {
        let size = SizeText.of(kilobytes: clean.kilobytes)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(clean
                .canPutBack ? "Moved \(clean.summary) to the Trash, \(size)." : "Deleted \(clean.summary), \(size).")
                .foregroundStyle(.muted)
            if clean.canPutBack {
                Button("Put Back") { Task { await self.cleaning.putBackParts(of: self.result.item) } }
                    .buttonStyle(.link)
                    .disabled(self.scan.isCleaning)
            }
        }
        .font(.caption)
    }
}
