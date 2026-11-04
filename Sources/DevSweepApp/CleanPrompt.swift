import DevSweepKit

/// The words of the questions asked before cleaning.
enum CleanPrompt {
    static func title(for pending: AppModel.PendingClean, size: String, moveToTrash: Bool) -> String {
        switch pending.stage {
        case let .quitApps(apps):
            "Quit \(self.names(apps.map(\.rawValue)))?"
        case .confirm:
            moveToTrash ? "Clean \(size)?" : "Delete \(size) for good?"
        }
    }

    static func message(for pending: AppModel.PendingClean, moveToTrash: Bool) -> String {
        if !pending.parts.isEmpty { return self.partsMessage(for: pending, moveToTrash: moveToTrash) }
        switch pending.stage {
        case let .quitApps(apps):
            let blocked = pending.items.filter(\.needsXcodeClosed).map(\.shortName)
            let verb = apps.count == 1 ? "is" : "are"
            return "\(self.names(blocked)) can't be cleaned while \(self.names(apps.map(\.rawValue))) \(verb) open. "
                + "Xcode asks to save unsaved work before it quits."
        case .confirm:
            if !moveToTrash {
                return "\(self.names(pending.items.map(\.shortName))) will be deleted and can't be put back. "
                    + "Each comes back as you build, resolve or download again."
            }
            let byTool = pending.items.filter(\.cleanedByItsTool)
            let rest = pending.items.filter { !$0.cleanedByItsTool }
            var message = "\(names(byTool.map(\.shortName))) \(byTool.count == 1 ? "is" : "are") removed by "
                + "\(self.names(byTool.map { $0 == .simulators ? "simctl" : "brew" })), so "
                + "\(byTool.count == 1 ? "it" : "they") can't be put back."
            if !rest.isEmpty { message += " The rest moves to the Trash." }
            return message
        }
    }

    /// The words for parts of DerivedData: by name up to three, by count past that.
    private static func partsMessage(for pending: AppModel.PendingClean, moveToTrash: Bool) -> String {
        switch pending.stage {
        case let .quitApps(apps):
            let verb = apps.count == 1 ? "is" : "are"
            return "\(self.capitalized(self.names(pending.blockedPartNames))) can't be cleaned while "
                + "\(self.names(apps.map(\.rawValue))) \(verb) open. Xcode asks to save unsaved work before it quits."
        case .confirm:
            let one = pending.parts.count == 1
            let names = pending.partNames.count <= 3
                ? self.names(pending.partNames) : AppModel.summary(of: pending.parts)
            let listed = self.capitalized(names)
            var message: String
            if moveToTrash {
                message = "\(listed) \(one ? "goes" : "go") to the Trash, so \(one ? "it" : "they") can be put back."
            } else {
                message = "\(listed) will be deleted and can't be put back. Each comes back as you build again; "
                message += "projects you no longer build stay gone."
            }
            if pending.xcodeOpen, one {
                let name = pending.partNames.first ?? "it"
                message += " Xcode is open: if \(name) is open in it, close it there first. Xcode builds it again "
                message += "either way."
            } else if pending.xcodeOpen {
                message += " Xcode is open: if any of them is open in it, close it there first. Xcode builds them "
                message += "again either way."
            }
            return message
        }
    }

    /// "the compilation cache" at the start of a sentence.
    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "A", "A and B", "A, B and C".
    static func names(_ list: [String]) -> String {
        switch list.count {
        case 0: ""
        case 1: list[0]
        default: list.dropLast().joined(separator: ", ") + " and " + list[list.count - 1]
        }
    }
}
