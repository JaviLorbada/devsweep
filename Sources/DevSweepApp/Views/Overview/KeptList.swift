import DevSweepKit
import SwiftUI

/// The build folders the scan kept because each holds a git repository,
/// each by the project it belongs to, with its size and where the
/// repository sits in it. None counts in the item's size, and none is
/// cleaned unless ticked here.
struct KeptList: View {
    @Environment(ScanModel.self) private var scan
    @Environment(MarksModel.self) private var marks
    let item: Item
    let folders: [KeptFolder]
    /// Whether they can be ticked: this scan's result, not the last one's.
    var selectable = false

    var body: some View {
        let names = PartsList.folderNames(self.folders.map(\.path))
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Kept")
            ForEach(self.folders, id: \.path) { folder in
                let name = names[folder.path] ?? folder.path
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if self.selectable {
                        Toggle("Mark \(name) for cleaning", isOn: Binding(
                            get: { self.marks.markedParts(of: self.item).contains(.folder(folder.path)) },
                            set: { self.marks.setMarked(.folder(folder.path), of: self.item, $0) }))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .disabled(self.scan.isCleaning || self.scan.isScanning)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 4)
                            Text(SizeText.of(kilobytes: folder.kilobytes))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        .font(.callout)
                        Text(self.scan.tilde(folder.path))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(self.scan.tilde(folder.path))
                        Text(folder.reason)
                            .font(.caption)
                            .foregroundStyle(.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
            Text("Your project's repository ignores a build folder, so it can't see a clone's edits or commits. "
                + "Check one before you tick it.")
                .font(.caption)
                .foregroundStyle(.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
