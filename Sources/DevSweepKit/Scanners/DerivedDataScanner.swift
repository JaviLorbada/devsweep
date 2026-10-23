import Foundation

/// Xcode's DerivedData, deleted as one folder, measured part by part.
public struct DerivedDataScanner: Scanner {
    public let item = Item.derivedData

    /// The DerivedData folder, unresolved: Xcode's custom location when it is
    /// set to an absolute or `~` path, the default one otherwise.
    func directory(in context: ScanContext) async -> String {
        let custom = await context.tools.xcodeDefaults.customDerivedDataLocation()
        if custom.hasPrefix("/") || custom.utf8.first == UInt8(ascii: "~") {
            return context.policy.expandTilde(custom)
        }
        return "\(context.home)/Library/Developer/Xcode/DerivedData"
    }

    public func location(in context: ScanContext) async -> String {
        await context.policy.tilde(self.directory(in: context))
    }

    public func collect(in context: ScanContext) async -> [String] {
        await context.existing([self.directory(in: context)])
    }

    public func scan(in context: ScanContext, progress: @escaping @Sendable (Int64) -> Void) async -> ItemResult {
        let directory = await directory(in: context)
        let paths = context.existing([directory])
        let location = context.policy.tilde(directory)
        guard let folder = paths.first else {
            return ItemResult(item: self.item, paths: [], kilobytes: 0, location: location)
        }
        // Measured entry by entry, once, for both the total and the breakdown.
        let (breakdown, known) = await Self.breakdown(of: folder, context: context, progress: progress)
        return ItemResult(
            item: self.item,
            paths: paths,
            kilobytes: breakdown.totalKilobytes,
            location: location,
            derivedData: breakdown,
            sizeKnown: known)
    }

    /// One part per entry in the folder: the shared compilation and module
    /// caches, a project folder when its `info.plist` names a workspace, other
    /// otherwise.
    static func breakdown(
        of folder: String,
        context: ScanContext,
        progress: @escaping @Sendable (Int64) -> Void) async -> (DerivedDataBreakdown, Bool)
    {
        // The glob `* .[!.]*`: every entry except names starting with "..".
        let names = context.files.childNames(folder).filter { !$0.hasPrefix("..") }
        let measured = await context.measure(names.map { "\(folder)/\($0)" }, progress: progress)

        var result = DerivedDataBreakdown()
        var projects: [DerivedDataProject] = []
        for (name, measurement) in zip(names, measured) {
            let kilobytes = measurement.kilobytes
            switch name {
            case "CompilationCache.noindex":
                result.compilationCacheKilobytes += kilobytes
            case "ModuleCache.noindex":
                result.moduleCacheKilobytes += kilobytes
            default:
                if let project = project(at: "\(folder)/\(name)", kilobytes: kilobytes, files: context.files) {
                    projects.append(project)
                } else {
                    result.otherKilobytes += kilobytes
                }
            }
        }

        // `sort -k1,1nr`: largest first, ties by the whole line in byte order.
        result.projects = projects.sorted { a, b in
            if a.kilobytes != b.kilobytes { return a.kilobytes > b.kilobytes }
            return "\(a.name)\t\(a.statusText)".utf8.lexicographicallyPrecedes("\(b.name)\t\(b.statusText)".utf8)
        }
        return (result, measured.allSatisfy(\.readable))
    }

    static func project(
        at entry: String,
        kilobytes: Int64,
        files: any FileSystemAccess = LiveFileSystem()) -> DerivedDataProject?
    {
        let plist = PropertyList.dictionary(at: "\(entry)/info.plist")
        guard let workspace = plist?["WorkspacePath"] as? String, !workspace.isEmpty else { return nil }

        let status: DerivedDataProject.Status
        if files.exists(workspace) {
            let day = PropertyList.dayPrefix(plist?["LastAccessedDate"])
            status = .built(day ?? DayFormat.local(secondsSince1970: files.modificationTime(entry)))
        } else {
            status = .gone
        }
        return DerivedDataProject(
            name: self.projectName(workspace),
            status: status,
            kilobytes: kilobytes,
            folder: entry,
            workspacePath: workspace)
    }

    /// `Folder/Project` from a workspace path such as `.../Folder/Project.xcodeproj`.
    static func projectName(_ workspacePath: String) -> String {
        let workspace = workspacePath.removingSuffix("/")
        let name = FileSystem.basename(workspace).removingSuffix(".xcodeproj")
        return "\(FileSystem.basename(FileSystem.dirname(workspace)))/\(name.removingSuffix(".xcworkspace"))"
    }
}

/// Reads plists the way `plutil -extract KEY raw` does for the keys DevSweep needs.
enum PropertyList {
    static func dictionary(at path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    static func string(at path: String, key: String) -> String? {
        guard let value = dictionary(at: path)?[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    /// The first ten characters `plutil` prints for a date or string value,
    /// or nil when there is no such value.
    static func dayPrefix(_ value: Any?) -> String? {
        let text: String
        switch value {
        case let date as Date: text = DayFormat.utc(date)
        case let string as String: text = string.prefixBytes(10)
        default: return nil
        }
        return text.isEmpty ? nil : text
    }
}
