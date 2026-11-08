import DevSweepKit
import Foundation
import Observation
import SwiftUI

/// A clean from the question to the end: quitting Xcode and Simulator when
/// an item needs them closed, asking first when nothing can be put back,
/// moving to the Trash or deleting, Put Back, and cleaning parts of an item.
/// It keeps what this session cleaned and the notices that follow.
@MainActor
@Observable
final class CleaningModel: CleaningTotals {
    /// Clean by moving to the Trash, so anything can be put back; off
    /// deletes for good. Starts as the preferences say; the overview's
    /// toggle changes it for this session.
    var moveToTrash: Bool
    /// A clean waiting on an answer, which the window asks.
    private(set) var pendingClean: PendingClean?
    /// What the window says after a clean that left something alone.
    private(set) var notice: Notice?
    private(set) var trashedThisSession: Int64 = 0
    private(set) var deletedThisSession: Int64 = 0
    /// Each item's last parts clean, which the inspector reports and can put
    /// back from the Trash.
    private(set) var partsCleans: [Item: PartsClean] = [:]
    private let scan: any ScanRows
    private let marks: any Marking
    private let apps: any RunningApps

    init(scan: any ScanRows, marks: any Marking, apps: any RunningApps, moveToTrash: Bool) {
        self.scan = scan
        self.marks = marks
        self.apps = apps
        self.moveToTrash = moveToTrash
    }

    var isCleaning: Bool {
        self.scan.isCleaning
    }

    /// The question was answered by closing it: nothing happens.
    func dismissPendingClean() {
        self.pendingClean = nil
    }

    func dismissNotice() {
        self.notice = nil
    }

    /// A new scan: the last parts cleans no longer match the rows.
    func reset() {
        self.partsCleans = [:]
    }

    func lastPartsClean(of item: Item) -> PartsClean? {
        self.partsCleans[item]
    }

    // MARK: Asking

    /// Starts cleaning `items`: asks to quit Xcode and Simulator when an Xcode
    /// item needs them closed, and asks to confirm anything that can't be put back.
    func requestClean(_ items: [Item]) async {
        guard !self.scan.isScanning, !self.isCleaning else { return }
        let items = items.filter { self.scan.rows[$0]?.isLive ?? false }
        guard !items.isEmpty else { return }
        await self.apps.refresh()
        let open = self.apps.open
        if items.contains(where: \.needsXcodeClosed), !open.isEmpty {
            self.pendingClean = PendingClean(items: items, stage: .quitApps(open), kilobytes: self.kilobytes(of: items))
        } else {
            self.confirmOrClean(items)
        }
    }

    /// Starts cleaning the ticked parts of `item`. Parts that need Xcode
    /// closed ask to quit it and Simulator, as the whole item does; the rest
    /// can go while Xcode is open, after a question when Xcode builds into
    /// the item, since it may have the project open.
    func requestCleanParts(of item: Item) async {
        guard !self.scan.isScanning, !self.isCleaning, self.scan.rows[item]?.isLive == true else { return }
        let parts = self.marks.markedParts(of: item)
        guard !parts.isEmpty else { return }
        await self.apps.refresh()
        let open = self.apps.open
        if parts.contains(where: { $0.needsXcodeClosed(in: item) }), !open.isEmpty {
            self.pendingClean = self.partsQuestion(parts, of: item, stage: .quitApps(open))
        } else {
            self.confirmOrClean([item], parts: parts)
        }
    }

    /// Quits Xcode and Simulator, then goes on with the clean.
    func quitAppsAndClean(_ pending: PendingClean) async {
        self.pendingClean = nil
        guard case let .quitApps(apps) = pending.stage else { return }
        if await self.apps.quit(apps) {
            self.confirmOrClean(pending.items, parts: pending.parts, afterAlert: true)
        } else {
            self.notice = Notice(
                title: "\(apps.map(\.rawValue).joined(separator: " and ")) didn't quit",
                message: "Nothing was cleaned. Quit them yourself, for example after saving your work, and clean "
                    + "again.")
        }
    }

    /// Goes on with the items, or the parts, that don't need Xcode closed.
    func cleanSkippingXcodeItems(_ pending: PendingClean) {
        self.pendingClean = nil
        if let item = pending.items.first, !pending.parts.isEmpty {
            let rest = pending.parts.filter { !$0.needsXcodeClosed(in: item) }
            if !rest.isEmpty { self.confirmOrClean(pending.items, parts: rest, afterAlert: true) }
            return
        }
        let rest = pending.items.filter { !$0.needsXcodeClosed }
        if !rest.isEmpty { self.confirmOrClean(rest, afterAlert: true) }
    }

    func confirmClean(_ pending: PendingClean) async {
        self.pendingClean = nil
        if let item = pending.items.first, !pending.parts.isEmpty {
            await self.performClean(pending.parts, of: item)
        } else {
            await self.performClean(pending.items)
        }
    }

    /// Whether these items need a yes first: everything does when deleting
    /// for good, and Simulators and Homebrew always, since their tools delete
    /// them. Parts of what Xcode builds into do while Xcode is open, which
    /// may have the project open.
    func needsConfirmation(_ items: [Item], parts: Set<ItemPart> = []) -> Bool {
        !self.moveToTrash || items.contains(where: \.cleanedByItsTool)
            || (!parts.isEmpty && self.apps.running.contains(.xcode) && items.contains(where: \.xcodeBuildsInto))
    }

    /// - Parameter afterAlert: an alert is closing, so give it a moment
    ///   before showing the next one.
    private func confirmOrClean(_ items: [Item], parts: Set<ItemPart> = [], afterAlert: Bool = false) {
        if self.needsConfirmation(items, parts: parts) {
            Task {
                if afterAlert { try? await Task.sleep(for: .milliseconds(300)) }
                if let item = items.first, !parts.isEmpty {
                    self.pendingClean = self.partsQuestion(parts, of: item, stage: .confirm)
                } else {
                    self.pendingClean = PendingClean(
                        items: items,
                        stage: .confirm,
                        kilobytes: self.kilobytes(of: items))
                }
            }
        } else if let item = items.first, !parts.isEmpty {
            Task { await self.performClean(parts, of: item) }
        } else {
            Task { await self.performClean(items) }
        }
    }

    /// What cleaning `items` whole would take.
    private func kilobytes(of items: [Item]) -> Int64 {
        items.compactMap { self.scan.rows[$0]?.kilobytes }.reduce(0, +)
    }

    /// The question about cleaning `parts` of `item`.
    private func partsQuestion(_ parts: Set<ItemPart>, of item: Item, stage: PendingClean.Stage) -> PendingClean {
        CleanPrompt.partsQuestion(
            parts,
            of: item,
            in: self.scan.rows[item]?.result,
            xcodeOpen: self.apps.running.contains(.xcode),
            stage: stage)
    }

    // MARK: Cleaning

    private func performClean(_ items: [Item]) async {
        guard let cleaner = self.scan.beginCleaning() else { return }
        let mode: CleanMode = self.moveToTrash ? .trash : .delete
        var problems: [String] = []

        for item in items {
            guard let row = self.scan.rows[item], row.isLive, let result = row.result else { continue }
            // Xcode may have been opened since the question was asked.
            if item.needsXcodeClosed {
                await self.apps.refresh()
                if !self.apps.running.isEmpty {
                    problems.append("Skipped \(item.name): \(self.apps.sentence)")
                    continue
                }
            }
            self.scan.startCleaning(item, kilobytes: nil)
            let outcome = await self.countingDown(item) { await cleaner.clean(result, mode: mode, progress: $0) }
            problems += outcome.warnings
            let removedSomething = !outcome.removed.isEmpty || outcome.toolSucceeded == true
            self.scan.finishCleaning(item, outcome: removedSomething ? outcome : nil)
            if removedSomething {
                withAnimation(Motion.animation(.easeInOut(duration: 0.4))) { self.marks.cleaned(item) }
                // What a parts clean put in the Trash went with the rest.
                self.partsCleans[item] = nil
                if outcome.canPutBack {
                    self.trashedThisSession += result.kilobytes
                } else {
                    self.deletedThisSession += result.kilobytes
                }
            }
        }

        self.scan.endCleaning(warnings: problems)
        self.report(problems)
    }

    private func performClean(_ parts: Set<ItemPart>, of item: Item) async {
        guard !self.isCleaning, let row = self.scan.rows[item], row.isLive, let result = row.result else { return }
        // Xcode may have been opened since the question was asked.
        if parts.contains(where: { $0.needsXcodeClosed(in: item) }) {
            await self.apps.refresh()
            if !self.apps.running.isEmpty {
                self.notice = Notice(title: "Nothing was cleaned", message: self.apps.sentence)
                return
            }
        }
        guard let cleaner = self.scan.beginCleaning() else { return }
        let mode: CleanMode = self.moveToTrash ? .trash : .delete
        self.scan.startCleaning(item, kilobytes: parts.reduce(0) { $0 + result.kilobytes(of: $1) })
        let outcome = await self.countingDown(item) {
            await cleaner.clean(parts, of: result, mode: mode, progress: $0)
        }
        let cleaned = outcome.cleaned
        let left = result.removing(cleaned)
        let freed = result.kilobytes - left.kilobytes
        self.scan.finishCleaningParts(item, left: left)
        withAnimation(Motion.animation(.easeInOut(duration: 0.4))) { self.marks.cleaned(cleaned, of: item) }
        if !cleaned.isEmpty {
            if outcome.outcome.canPutBack {
                self.trashedThisSession += freed
            } else {
                self.deletedThisSession += freed
            }
            self.partsCleans[item] = PartsClean(
                outcome: outcome,
                before: result,
                kilobytes: freed,
                summary: CleanPrompt.partsSummary(cleaned, in: item))
        }
        self.scan.endCleaning(warnings: outcome.outcome.warnings)
        self.report(outcome.outcome.warnings)
    }

    /// Runs a clean with `item`'s row counting down as it reports. The
    /// removal reports from several threads; the row shows the latest count
    /// about ten times a second.
    private func countingDown<Outcome>(
        _ item: Item,
        _ clean: (@escaping @Sendable (Int64) -> Void) async -> Outcome) async -> Outcome
    {
        let (removed, reporter) = AsyncStream.makeStream(of: Int64.self, bufferingPolicy: .bufferingNewest(1))
        let counter = Task {
            for await bytes in removed {
                self.scan.cleaningProgress(item, removedBytes: bytes)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        let outcome = await clean { reporter.yield($0) }
        reporter.finish()
        counter.cancel()
        return outcome
    }

    private func report(_ problems: [String]) {
        guard !problems.isEmpty else { return }
        self.notice = Notice(title: "Some things were left alone", message: problems.joined(separator: "\n"))
    }

    // MARK: Put Back

    /// Moves what cleaning `item` put in the Trash back where it was. It
    /// takes the rows as a clean does, so it waits for none and none for it.
    func putBack(_ item: Item) async {
        guard let row = self.scan.rows[item], row.canPutBack, let outcome = row.outcome,
              let cleaner = self.scan.beginCleaning()
        else { return }
        let result = await cleaner.putBack(outcome)
        if !result.restored.isEmpty {
            self.scan.putBack(item)
            self.trashedThisSession = max(0, self.trashedThisSession - row.kilobytes)
        }
        self.scan.endCleaning(warnings: [])
        self.reportPutBackFailures(result.failed)
    }

    /// Moves what the last parts clean of `item` put in the Trash back where it was.
    func putBackParts(of item: Item) async {
        guard let clean = self.partsCleans[item], clean.canPutBack, let result = self.scan.rows[item]?.result,
              let cleaner = self.scan.beginCleaning()
        else { return }
        let putBack = await cleaner.putBack(clean.outcome.outcome)
        let restored = clean.outcome.restored(by: putBack)
        let whole = result.restoring(restored, from: clean.before)
        self.scan.putBackParts(item, whole: whole)
        self.trashedThisSession = max(0, self.trashedThisSession - (whole.kilobytes - result.kilobytes))
        self.partsCleans[item] = nil
        self.scan.endCleaning(warnings: [])
        self.reportPutBackFailures(putBack.failed)
    }

    private func reportPutBackFailures(_ failed: [String]) {
        guard !failed.isEmpty else { return }
        self.notice = Notice(
            title: "Some folders couldn't be put back",
            message: "Something now stands where they were, or the folder that held them changed. They are still "
                + "in the Trash:\n"
                + failed.map(self.scan.tilde).joined(separator: "\n"))
    }
}

/// The questions a clean waits on, and what the window says after.
extension CleaningModel {
    /// A clean waiting on an answer: quit Xcode first, or confirm.
    struct PendingClean: Identifiable {
        enum Stage {
            case quitApps([DeveloperApp])
            case confirm
        }

        let id = UUID()
        let items: [Item]
        let stage: Stage
        /// What the clean would take, as the scan measured it: the items, or
        /// just the parts.
        var kilobytes: Int64 = 0
        /// Parts of the item to clean instead of the whole of it.
        var parts: Set<ItemPart> = []
        /// What the question calls those parts: "DerivedData for Atlas",
        /// "App-1/.build and App-2/.build", "5 .build folders".
        var partsSubject = ""
        /// Whether that subject takes "go" rather than "goes".
        var partsPlural = false
        /// Those of them that need Xcode closed, by name.
        var blockedPartNames: [String] = []
        /// Asked while Xcode is open, which may have the project open.
        var xcodeOpen = false
        /// The project to close in Xcode, for one part; empty for several.
        var xcodeName = ""

        /// Whether some of it can be cleaned with Xcode and Simulator open.
        var hasOthers: Bool {
            guard let item = self.items.first, !self.parts.isEmpty else {
                return self.items.contains { !$0.needsXcodeClosed }
            }
            return self.parts.contains { !$0.needsXcodeClosed(in: item) }
        }
    }

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// A clean of some parts of an item, which the inspector reports.
    struct PartsClean {
        let outcome: PartsCleanOutcome
        /// The item's result before, to put parts back as they were measured.
        let before: ItemResult
        /// What it took from the item's size.
        let kilobytes: Int64
        /// "2 projects", "3 folders".
        let summary: String

        var canPutBack: Bool {
            self.outcome.outcome.canPutBack
        }
    }
}
