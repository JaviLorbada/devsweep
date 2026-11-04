import Foundation

/// A part of DerivedData that can be cleaned on its own: the parts the
/// breakdown measures.
public enum DerivedDataPart: Hashable, Sendable {
    case compilationCache
    case moduleCache
    /// A project's folder, by its path inside DerivedData.
    case project(String)
    /// Everything that is neither a shared cache nor a project.
    case other

    /// The shared caches serve every project, and what other holds is
    /// unknown, so Xcode has to be closed to clean them; a project's own
    /// folder can go while Xcode works on another.
    public var needsXcodeClosed: Bool {
        if case .project = self { return false }
        return true
    }
}

extension DerivedDataBreakdown {
    public func kilobytes(of part: DerivedDataPart) -> Int64 {
        switch part {
        case .compilationCache: self.compilationCacheKilobytes
        case .moduleCache: self.moduleCacheKilobytes
        case let .project(folder): self.projects.first { $0.folder == folder }?.kilobytes ?? 0
        case .other: self.otherKilobytes
        }
    }

    /// The breakdown once `parts` are gone.
    public func removing(_ parts: Set<DerivedDataPart>) -> DerivedDataBreakdown {
        var result = self
        for part in parts {
            switch part {
            case .compilationCache: result.compilationCacheKilobytes = 0
            case .moduleCache: result.moduleCacheKilobytes = 0
            case let .project(folder): result.projects.removeAll { $0.folder == folder }
            case .other: result.otherKilobytes = 0
            }
        }
        return result
    }

    /// The breakdown with `parts` back as `original` measured them.
    public func restoring(_ parts: Set<DerivedDataPart>, from original: DerivedDataBreakdown) -> DerivedDataBreakdown {
        var result = self
        for part in parts {
            switch part {
            case .compilationCache: result.compilationCacheKilobytes = original.compilationCacheKilobytes
            case .moduleCache: result.moduleCacheKilobytes = original.moduleCacheKilobytes
            case let .project(folder):
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

/// What cleaning parts of DerivedData did.
public struct PartsCleanOutcome: Sendable {
    public var outcome: CleanOutcome
    /// The folders each part was cleaned through.
    public var paths: [DerivedDataPart: [String]]

    /// The parts that are gone: none of their folders failed or was skipped.
    /// A project left alone for lying outside the folder had none to go.
    public var cleaned: Set<DerivedDataPart> {
        let kept = Set(self.outcome.failed + self.outcome.skipped)
        return Set(self.paths.filter { part, folders in
            if case .project = part, folders.isEmpty { return false }
            return !folders.contains(where: kept.contains)
        }.keys)
    }

    /// The cleaned parts a put back brought back whole.
    public func restored(by putBack: PutBackOutcome) -> Set<DerivedDataPart> {
        let restored = Set(putBack.restored)
        let removed = Set(self.outcome.removed.map(\.original))
        return self.cleaned.filter { part in
            self.paths[part, default: []].filter(removed.contains).allSatisfy(restored.contains)
        }
    }
}

extension Engine {
    /// Cleans some parts of a scanned DerivedData folder. Each part's folders
    /// go as a whole item's do, checked with the policy right before; a
    /// project folder that isn't directly inside the scanned folder is left
    /// alone.
    public func clean(
        _ parts: Set<DerivedDataPart>,
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

    func paths(of parts: Set<DerivedDataPart>, in result: ItemResult) -> [DerivedDataPart: [String]] {
        guard result.item == .derivedData, let folder = result.paths.first else { return [:] }
        var paths: [DerivedDataPart: [String]] = [:]
        for part in parts {
            switch part {
            case .compilationCache: paths[part] = ["\(folder)/CompilationCache.noindex"]
            case .moduleCache: paths[part] = ["\(folder)/ModuleCache.noindex"]
            case let .project(path):
                paths[part] = FileSystem.dirname(path).bytesEqual(folder) && path != folder ? [path] : []
            case .other: paths[part] = DerivedDataScanner.otherEntries(of: folder, files: dependencies.files)
            }
        }
        return paths
    }
}
