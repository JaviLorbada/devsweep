import Dispatch
import Foundation
import Synchronization

public enum CleanMode: Sendable, Equatable {
    /// Move to the Trash, so each folder can be put back.
    case trash
    /// Delete for good, like `rm -rf`.
    case delete
}

/// What cleaning one item did.
public struct CleanOutcome: Sendable {
    public struct Removed: Sendable, Equatable {
        /// The resolved path the folder had.
        public var original: String
        /// Where it is now, for `.trash`; nil when it was deleted.
        public var trashed: String?
    }

    public var item: Item
    public var mode: CleanMode
    public var removed: [Removed] = []
    /// Paths left alone because they changed since the scan.
    public var skipped: [String] = []
    /// Paths that could not be fully removed.
    public var failed: [String] = []
    /// For simulators and Homebrew: whether simctl or brew reported success.
    public var toolSucceeded: Bool?
    /// The bash script's warnings, without the "<command>: " prefix.
    public var warnings: [String] = []

    /// Whether everything removed can be put back.
    public var canPutBack: Bool {
        self.mode == .trash && !self.removed.isEmpty && self.removed.allSatisfy { $0.trashed != nil }
    }
}

extension Engine {
    /// Cleans one scanned item. Every path is checked again with the policy
    /// right before it goes; one that no longer resolves to the same place is
    /// skipped with a warning. Simulators go through `simctl delete
    /// unavailable` and Homebrew through `brew cleanup` whatever the mode, since
    /// those tools own their files.
    ///
    /// - Parameter progress: while deleting, the bytes removed so far across
    ///   the item's paths, several times a second, from any thread.
    public func clean(
        _ result: ItemResult,
        mode: CleanMode,
        progress: (@Sendable (Int64) -> Void)? = nil) async -> CleanOutcome
    {
        var outcome = CleanOutcome(item: result.item, mode: mode)
        let tally = Tally(progress)
        switch result.item {
        case .simulators:
            let succeeded = await tools.simctl.deleteUnavailable()
            outcome.toolSucceeded = succeeded
            if !succeeded { outcome.warnings.append("Couldn't delete unavailable simulators.") }
        case .homebrew:
            let succeeded = await tools.brew.cleanup()
            outcome.toolSucceeded = succeeded
            if !succeeded { outcome.warnings.append("brew cleanup failed. Run it yourself to see why.") }
        default:
            for path in result.paths {
                // Already gone, e.g. inside a folder deleted earlier in this run.
                guard FileSystem.existsOrIsSymlink(path) else { continue }
                // The list holds resolved paths, so any change since the scan
                // (like a folder swapped for a symlink) makes this check fail.
                guard policy.stillSafe(path) else {
                    outcome.skipped.append(path)
                    outcome.warnings.append(
                        "Skipped \(policy.tilde(path)): it changed since the scan and may now lead outside your home "
                            + "folder.")
                    continue
                }
                switch mode {
                case .delete:
                    do {
                        try await Self.offPool { [files = dependencies.files] in
                            try files.remove(path, progress: tally.report)
                        }
                        outcome.removed.append(.init(original: path, trashed: nil))
                    } catch {
                        outcome.failed.append(path)
                        outcome.warnings.append("Couldn't fully delete \(policy.tilde(path))")
                    }
                    tally.finishPath()
                case .trash:
                    do {
                        let trashed = try tools.trash.trash(path)
                        outcome.removed.append(.init(original: path, trashed: trashed))
                    } catch {
                        outcome.failed.append(path)
                        outcome.warnings.append("Couldn't move \(policy.tilde(path)) to the Trash")
                    }
                }
            }
        }
        return outcome
    }

    /// Runs `work` on a GCD thread, so a delete that takes a minute doesn't
    /// hold one of the few threads Swift concurrency runs tasks on.
    private static func offPool(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    /// Moves what a Trash clean removed back where it was. A folder is put
    /// back only when nothing has taken its place and its parent still
    /// resolves to the same folder inside home.
    public func putBack(_ outcome: CleanOutcome) async -> PutBackOutcome {
        var result = PutBackOutcome()
        for removed in outcome.removed {
            guard let trashed = removed.trashed else { continue }
            let parent = FileSystem.dirname(removed.original)
            let parentIntact = FileSystem.physicalDirectory(parent)
                .map { $0.bytesEqual(parent) && policy.isInsideOrHome($0) } ?? false
            guard parentIntact, !FileSystem.existsOrIsSymlink(removed.original),
                  FileSystem.existsOrIsSymlink(trashed)
            else {
                result.failed.append(removed.original)
                continue
            }
            do {
                try tools.trash.putBack(trashed, to: removed.original)
                result.restored.append(removed.original)
            } catch {
                result.failed.append(removed.original)
            }
        }
        return result
    }
}

/// Adds up the bytes each deleted path reports into one running total.
private final class Tally: Sendable {
    private let progress: (@Sendable (Int64) -> Void)?
    private let bytes = Mutex((finished: Int64(0), current: Int64(0)))

    init(_ progress: (@Sendable (Int64) -> Void)?) {
        self.progress = progress
    }

    @Sendable func report(_ current: Int64) {
        guard let progress else { return }
        // Threads report out of order now and then; the total only grows,
        // and goes out under the lock so it arrives in order too.
        self.bytes.withLock {
            $0.current = max($0.current, current)
            progress($0.finished + $0.current)
        }
    }

    func finishPath() {
        self.bytes.withLock {
            $0.finished += $0.current
            $0.current = 0
        }
    }
}

public struct PutBackOutcome: Sendable, Equatable {
    public var restored: [String] = []
    public var failed: [String] = []
}
