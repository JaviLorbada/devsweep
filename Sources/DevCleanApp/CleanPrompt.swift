import DevCleanKit

/// The words of the questions asked before cleaning.
enum CleanPrompt {
    static func title(for pending: AppModel.PendingClean, size: String, moveToTrash: Bool) -> String {
        switch pending.stage {
        case .quitApps(let apps):
            "Quit \(names(apps.map(\.rawValue)))?"
        case .confirm:
            moveToTrash ? "Clean \(size)?" : "Delete \(size) for good?"
        }
    }

    static func message(for pending: AppModel.PendingClean, moveToTrash: Bool) -> String {
        switch pending.stage {
        case .quitApps(let apps):
            let blocked = pending.items.filter(\.needsXcodeClosed).map(\.shortName)
            let verb = apps.count == 1 ? "is" : "are"
            return "\(names(blocked)) can't be cleaned while \(names(apps.map(\.rawValue))) \(verb) open. "
                + "Xcode asks to save unsaved work before it quits."
        case .confirm:
            if !moveToTrash {
                return "\(names(pending.items.map(\.shortName))) will be deleted and can't be put back. "
                    + "Each comes back as you build, resolve or download again."
            }
            let byTool = pending.items.filter(\.cleanedByItsTool)
            let rest = pending.items.filter { !$0.cleanedByItsTool }
            var message = "\(names(byTool.map(\.shortName))) \(byTool.count == 1 ? "is" : "are") removed by "
                + "\(names(byTool.map { $0 == .simulators ? "simctl" : "brew" })), so \(byTool.count == 1 ? "it" : "they") can't be put back."
            if !rest.isEmpty { message += " The rest moves to the Trash." }
            return message
        }
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
