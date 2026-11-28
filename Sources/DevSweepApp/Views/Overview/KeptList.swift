import DevSweepKit
import SwiftUI

/// The build folders the scan kept because each holds a git repository,
/// each by the project it belongs to, with its size and where the
/// repository sits in it, to tick and clean on its own. Nothing shows when
/// the item kept none.
struct KeptList: View {
    @Environment(KeptFoldersViewModel.self) private var kept
    let item: Item

    var body: some View {
        let lines = self.kept.lines(of: self.item)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Kept")
                ForEach(lines) { line in
                    self.line(line)
                }
                Text("Your project's repository ignores a build folder, so it can't see a clone's edits or commits. "
                    + "Check one before you clean it.")
                    .font(.caption)
                    .foregroundStyle(.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func line(_ line: KeptFoldersViewModel.Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if self.kept.showsTicks(for: self.item) {
                Toggle("Mark \(line.name) for cleaning", isOn: Binding(
                    get: { self.kept.isMarked(line, of: self.item) },
                    set: { self.kept.setMarked(line, of: self.item, $0) }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!self.kept.canTick)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(line.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(line.size)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .font(.callout)
                Text(line.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(line.path)
                Text(line.reason)
                    .font(.caption)
                    .foregroundStyle(.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
