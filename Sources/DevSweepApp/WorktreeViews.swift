import DevSweepKit
import SwiftUI

// The git worktrees found through the project folders: those of the
// repositories in them, and those in a folder of worktrees. DevSweep lists
// them all and removes one only when asked, with git's own `worktree
// remove`, and only when nothing in it would be lost.

struct WorktreesView: View {
    var body: some View {
        ScrollView { WorktreesContent() }
    }
}

struct WorktreesContent: View {
    @Environment(ScanModel.self) private var scan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExtrasCard(
                title: "Worktrees",
                note: "found through your project folders",
                rowCount: self.scan.extras?.worktrees.count ?? 0)
            {
                if let worktrees = scan.extras?.worktrees, !worktrees.isEmpty {
                    let largest = Double(worktrees.map(\.kilobytes).max() ?? 1)
                    ForEach(worktrees) { worktree in
                        Divider().opacity(0.6)
                        WorktreeRow(worktree: worktree, largest: largest)
                    }
                } else {
                    EmptyExtrasRow(text: self.scan.isLoadingExtras ? "Listing worktrees…" : "No worktrees found.")
                }
            }
            Text(self.isEmpty
                ? WorktreeWords.whereFound
                : "Remove keeps the branch and runs only when there's nothing to lose: no changes waiting to be "
                + "committed, and every commit on a branch.")
                .font(.callout)
                .foregroundStyle(.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    /// Listed, and none found.
    private var isEmpty: Bool {
        !self.scan.isLoadingExtras && (self.scan.extras?.worktrees.isEmpty ?? false)
    }
}

private struct WorktreeRow: View {
    @Environment(WindowViewModel.self) private var window
    @Environment(WorktreesViewModel.self) private var worktrees
    @Environment(\.extrasColumns) private var columns
    let worktree: GitWorktree
    let largest: Double

    var body: some View {
        let kept = self.worktree.keptBecause
        let selected = self.window.screen == .worktrees && self.worktrees.current?.id == self.worktree.id
        let tint: Color = kept == nil ? .orange : .secondary.opacity(0.6)
        HStack(spacing: 12) {
            Dot(color: tint)
            // The reason or the branch gives way first, then the name truncates.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.worktree.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle).layoutPriority(2)
                Text(kept ?? WorktreeWords.origin(self.worktree))
                    .font(.caption)
                    .foregroundStyle(.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if self.columns.showsDate {
                Text(self.worktree.lastCommit.map { "committed \(DayFormat.utc($0))" } ?? "no commits")
                    .font(.callout)
                    .foregroundStyle(.muted)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
            }
            if self.columns.showsBar {
                ThinBar(fraction: Double(self.worktree.kilobytes) / max(self.largest, 1), color: tint)
                    .frame(width: 100)
            }
            Text(SizeText.of(kilobytes: self.worktree.kilobytes))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
            Group {
                if kept != nil {
                    Color.clear
                } else if self.columns == .compact {
                    Button("Remove Worktree", systemImage: "trash") { self.askToRemove() }
                        .labelStyle(.iconOnly)
                        .help("Remove Worktree")
                } else {
                    Button("Remove Worktree") { self.askToRemove() }
                }
            }
            .controlSize(.small)
            .rowControl()
            .frame(width: self.columns == .compact ? 28 : 128)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .tableRowSelection(selected)
        .contentShape(Rectangle())
        .onTapGesture { self.worktrees.select(self.worktree) }
        .focusable()
        .onKeyPress(.space) { self.worktrees.select(self.worktree); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(self.worktree.name), \(SizeText.of(kilobytes: self.worktree.kilobytes))\(kept.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Select") { self.worktrees.select(self.worktree) }
    }

    private func askToRemove() {
        self.worktrees.askToRemove(self.worktree)
    }
}

struct WorktreeInspector: View {
    @Environment(WorktreesViewModel.self) private var worktrees
    @Environment(ScanModel.self) private var scan

    var body: some View {
        if let worktree = worktrees.current {
            // Scrolls, so the column never asks the window for the height of its text.
            ScrollView {
                WorktreeDetails(worktree: worktree)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .safeAreaBar(edge: .bottom) {
                Button("Remove Worktree") { self.worktrees.removal.ask(worktree) }
                    .buttonStyle(.prominentAction)
                    .controlSize(.large)
                    .disabled(worktree.keptBecause != nil)
                    .help(worktree.keptBecause
                        .map { "\($0), so it stays." } ?? "Removes it with git; the branch stays.")
                    .frame(maxWidth: .infinity)
                    .padding(18)
            }
        } else {
            ContentUnavailableView(
                "No worktree",
                systemImage: "arrow.triangle.branch",
                description: Text(self.scan.isLoadingExtras ? "Listing worktrees…" : "No worktrees found."))
        }
    }
}

/// What the inspector says about one worktree.
struct WorktreeDetails: View {
    @Environment(ScanModel.self) private var scan
    let worktree: GitWorktree

    var body: some View {
        let kept = self.worktree.keptBecause
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Dot(color: kept == nil ? .orange : .secondary.opacity(0.6))
                Eyebrow(text: "Git worktree")
            }
            Text(self.worktree.name).font(.title3.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(SizeText.of(kilobytes: self.worktree.kilobytes))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                Text(kept == nil ? "nothing to lose" : "keeps work")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(kept == nil ? AnyShapeStyle(.orange) : AnyShapeStyle(.muted))
            }
            Section("Repository") {
                Text("\(self.worktree.repositoryName), " + (self.worktree.branch.map { "branch \($0)" } ?? "detached"))
                Text(self.scan.tilde(self.worktree.repository))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            Section("Where") {
                Text(self.scan.tilde(self.worktree.path))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button("Reveal in Finder") { Finder.reveal([self.worktree.path]) }
                    .buttonStyle(.link)
            }
            Section(kept == nil ? "What happens" : "Why it stays") {
                Text(WorktreeWords.whatHappens(self.worktree))
            }
            Section("Runs") {
                Text(self.scan.policy.map { self.worktree.removalCommand(policy: $0) } ?? "")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, WindowLayout.inspectorTopPadding)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private struct Section<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content

        init(_ title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: self.title)
                self.content
                    .font(.callout)
                    .foregroundStyle(.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct RemoveWorktreeSheet: View {
    @Environment(WorktreesViewModel.self) private var worktrees
    @Environment(ScanModel.self) private var scan
    @Environment(\.dismiss) private var dismiss
    let worktree: GitWorktree

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remove the worktree \(self.worktree.name)?")
                .font(.title3.weight(.semibold))
            Text(
                "This frees \(SizeText.of(kilobytes: self.worktree.kilobytes)). "
                    + WorktreeWords.whatHappens(self.worktree))
                .foregroundStyle(.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "Runs")
                Text(self.scan.policy.map { self.worktree.removalCommand(policy: $0) } ?? "")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
            }
            if let error = worktrees.removal.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if self.worktrees.removal.isRemoving {
                    ProgressView().controlSize(.small)
                    Text("Removing…").foregroundStyle(.muted)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    self.worktrees.removal.clearError()
                    self.dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Remove Worktree", role: .destructive) {
                    Task { await self.worktrees.remove(self.worktree) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(self.worktrees.removal.isRemoving)
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(self.worktrees.removal.isRemoving)
    }
}

enum WorktreeWords {
    /// Where worktrees are found, said under the list when none were.
    static let whereFound = "Worktrees show through their repositories in your project folders, wherever they "
        + "live. If a tool keeps its worktrees in a folder of its own, add that folder in Settings > Folders."

    /// The screen's subtitle and the sidebar row's help: what can go, then what
    /// stays. "1.2 GB in 2 worktrees with nothing to lose. 3 more, 1.9 GB,
    /// keep work, so they stay." With none, the list itself says so.
    static func summary(_ worktrees: [GitWorktree]) -> String {
        let removable = worktrees.filter { $0.keptBecause == nil }
        let kept = worktrees.filter { $0.keptBecause != nil }
        let stays = kept.count == 1 ? "keeps work, so it stays" : "keep work, so they stay"
        switch (removable.isEmpty, kept.isEmpty) {
        case (true, true):
            return "Nothing to remove."
        case (true, false):
            return "\(self.size(kept)) in \(self.count(kept)) that \(stays)."
        case (false, true):
            return "\(self.size(removable)) in \(self.count(removable)) with nothing to lose."
        case (false, false):
            return "\(self.size(removable)) in \(self.count(removable)) with nothing to lose. "
                + "\(kept.count) more, \(self.size(kept)), \(stays)."
        }
    }

    private static func size(_ worktrees: [GitWorktree]) -> String {
        SizeText.of(kilobytes: worktrees.reduce(0) { $0 + $1.kilobytes })
    }

    private static func count(_ worktrees: [GitWorktree]) -> String {
        worktrees.count == 1 ? "1 worktree" : "\(worktrees.count) worktrees"
    }

    /// "Atlas, fix-login": its repository and branch, for a row.
    static func origin(_ worktree: GitWorktree) -> String {
        "\(worktree.repositoryName), \(worktree.branch ?? "detached")"
    }

    /// What removing it does, or why DevSweep keeps it.
    static func whatHappens(_ worktree: GitWorktree) -> String {
        if worktree.isLocked {
            return "It's locked with git worktree lock, so git keeps it until it's unlocked."
        }
        guard let changes = worktree.changes else {
            return "Git couldn't say whether it has changes, so it stays."
        }
        if changes > 0 {
            let count = changes == 1 ? "a change" : "\(changes) changes"
            let them = changes == 1 ? "it" : "them"
            return "It has \(count) not committed. Commit or discard \(them) in the worktree, and it can go."
        }
        if !worktree.commitsKept {
            return "It has commits on no branch, which removing it would lose. Make a branch for them first."
        }
        let kept = worktree.branch.map { "The branch \($0) stays in the repository" }
            ?? "A branch already holds its commits"
        return "Git removes the folder, with the dependencies and build output in it. \(kept), so nothing "
            + "committed is lost."
    }
}
