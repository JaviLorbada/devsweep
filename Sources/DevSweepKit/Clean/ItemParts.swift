import Foundation

/// A part of an item that can be cleaned on its own: one of its folders, or
/// in DerivedData a shared cache or the rest.
public enum ItemPart: Hashable, Sendable {
    /// DerivedData's compilation cache, shared by every project.
    case compilationCache
    /// DerivedData's module cache, shared by every project.
    case moduleCache
    /// A folder: a project's inside DerivedData, or one of an item's own,
    /// such as a `.build` folder.
    case folder(String)
    /// The rest of DerivedData: neither a shared cache nor a project.
    case other

    /// Whether Xcode has to be closed to clean it from `item`. The shared
    /// caches serve every project, and what the rest holds is unknown; a
    /// project's folder can go while Xcode works on another, and any other
    /// folder needs Xcode closed only when its whole item does.
    public func needsXcodeClosed(in item: Item) -> Bool {
        guard case .folder = self else { return true }
        return item != .derivedData && item.needsXcodeClosed
    }
}

extension DerivedDataBreakdown {
    public func kilobytes(of part: ItemPart) -> Int64 {
        switch part {
        case .compilationCache: self.compilationCacheKilobytes
        case .moduleCache: self.moduleCacheKilobytes
        case let .folder(folder): self.projects.first { $0.folder == folder }?.kilobytes ?? 0
        case .other: self.otherKilobytes
        }
    }

    /// The breakdown once `parts` are gone.
    public func removing(_ parts: Set<ItemPart>) -> DerivedDataBreakdown {
        var result = self
        for part in parts {
            switch part {
            case .compilationCache: result.compilationCacheKilobytes = 0
            case .moduleCache: result.moduleCacheKilobytes = 0
            case let .folder(folder): result.projects.removeAll { $0.folder == folder }
            case .other: result.otherKilobytes = 0
            }
        }
        return result
    }

    /// The breakdown with `parts` back as `original` measured them.
    public func restoring(_ parts: Set<ItemPart>, from original: DerivedDataBreakdown) -> DerivedDataBreakdown {
        var result = self
        for part in parts {
            switch part {
            case .compilationCache: result.compilationCacheKilobytes = original.compilationCacheKilobytes
            case .moduleCache: result.moduleCacheKilobytes = original.moduleCacheKilobytes
            case let .folder(folder):
                if let project = original.projects.first(where: { $0.folder == folder }),
                   !result.projects.contains(where: { $0.folder == folder })
                {
                    result.projects.append(project)
                }
            case .other: result.otherKilobytes = original.otherKilobytes
            }
        }
        result.projects = DerivedDataScanner.sorted(result.projects)
        return result
    }
}

extension ItemResult {
    /// What a part takes: from DerivedData's breakdown, or the folder's own
    /// size when the scan measured each folder.
    public func kilobytes(of part: ItemPart) -> Int64 {
        if let derivedData { return derivedData.kilobytes(of: part) }
        guard case let .folder(path) = part else { return 0 }
        return self.folderKilobytes?[path] ?? 0
    }

    /// The result once `parts` are gone, so the numbers drop without a scan.
    public func removing(_ parts: Set<ItemPart>) -> ItemResult {
        var result = self
        result.kilobytes -= parts.reduce(0) { $0 + self.kilobytes(of: $1) }
        if let derivedData {
            result.derivedData = derivedData.removing(parts)
        } else {
            for case let .folder(path) in parts {
                result.paths.removeAll { $0 == path }
                result.folderKilobytes?[path] = nil
            }
        }
        return result
    }

    /// The result with `parts` back as `before` measured them.
    public func restoring(_ parts: Set<ItemPart>, from before: ItemResult) -> ItemResult {
        var result = self
        result.kilobytes += parts.reduce(0) { $0 + before.kilobytes(of: $1) }
        if let derivedData, let original = before.derivedData {
            result.derivedData = derivedData.restoring(parts, from: original)
        } else {
            for case let .folder(path) in parts where before.paths.contains(path) && !result.paths.contains(path) {
                result.paths.append(path)
                result.folderKilobytes?[path] = before.folderKilobytes?[path]
            }
            result.paths = result.paths.sortedBytewise()
        }
        return result
    }
}

/// What cleaning parts of an item did.
public struct PartsCleanOutcome: Sendable {
    public var outcome: CleanOutcome
    /// The folders each part was cleaned through.
    public var paths: [ItemPart: [String]]

    /// The parts that are gone: none of their folders failed or was skipped.
    /// A folder left alone for not being one of the item's had none to go.
    public var cleaned: Set<ItemPart> {
        let kept = Set(self.outcome.failed + self.outcome.skipped)
        return Set(self.paths.filter { part, folders in
            if case .folder = part, folders.isEmpty { return false }
            return !folders.contains(where: kept.contains)
        }.keys)
    }

    /// The cleaned parts a put back brought back whole.
    public func restored(by putBack: PutBackOutcome) -> Set<ItemPart> {
        let restored = Set(putBack.restored)
        let removed = Set(self.outcome.removed.map(\.original))
        return self.cleaned.filter { part in
            self.paths[part, default: []].filter(removed.contains).allSatisfy(restored.contains)
        }
    }
}

extension Engine {
    /// Cleans some parts of a scanned item: some of its folders, or parts of
    /// DerivedData. Each part's folders go as a whole item's do, checked
    /// with the policy right before. A folder that isn't one of the item's,
    /// or for DerivedData directly inside the scanned folder, is left alone.
    public func clean(
        _ parts: Set<ItemPart>,
        of result: ItemResult,
        mode: CleanMode,
        progress: (@Sendable (Int64) -> Void)? = nil) async -> PartsCleanOutcome
    {
        let paths = self.paths(of: parts, in: result)
        var partial = result
        partial.paths = paths.values.flatMap(\.self).sortedBytewise()
        let outcome = await self.clean(partial, mode: mode, progress: progress)
        return PartsCleanOutcome(outcome: outcome, paths: paths)
    }

    func paths(of parts: Set<ItemPart>, in result: ItemResult) -> [ItemPart: [String]] {
        guard let first = result.paths.first else { return [:] }
        let isDerivedData = result.item == .derivedData
        var paths: [ItemPart: [String]] = [:]
        for part in parts {
            switch part {
            case let .folder(path) where isDerivedData:
                paths[part] = FileSystem.dirname(path).bytesEqual(first) && !path.bytesEqual(first) ? [path] : []
            case let .folder(path):
                paths[part] = result.paths.contains { $0.bytesEqual(path) } ? [path] : []
            case .compilationCache where isDerivedData: paths[part] = ["\(first)/CompilationCache.noindex"]
            case .moduleCache where isDerivedData: paths[part] = ["\(first)/ModuleCache.noindex"]
            case .other where isDerivedData:
                paths[part] = DerivedDataScanner.otherEntries(of: first, files: dependencies.files)
            case .compilationCache, .moduleCache, .other: paths[part] = []
            }
        }
        return paths
    }
}
