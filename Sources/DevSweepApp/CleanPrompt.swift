import DevSweepKit
import Foundation

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
            let subject = self.capitalized(pending.partsSubject)
            let plural = pending.partsPlural
            var message: String
            if moveToTrash {
                message = "\(subject) \(plural ? "go" : "goes") to the Trash, so "
                message += "\(plural ? "they" : "it") can be put back."
            } else {
                message = "\(subject) will be deleted and can't be put back. Each comes back as you build again; "
                message += "projects you no longer build stay gone."
            }
            if pending.xcodeOpen, !pending.xcodeName.isEmpty {
                message += " Xcode is open: if \(pending.xcodeName) is open in it, close it there first. Xcode builds "
                message += "it again either way."
            } else if pending.xcodeOpen {
                message += " Xcode is open: if one of these projects is open in it, close it there first. Xcode "
                message += "builds them again either way."
            }
            return message
        }
    }

    /// "1 project", "2 projects", "3 parts" once a cache or the rest of
    /// DerivedData is among them; "2 folders" for an item's folders.
    static func partsSummary(_ parts: Set<ItemPart>, in item: Item) -> String {
        let noun = item != .derivedData ? "folder" : self.allProjects(parts) ? "project" : "part"
        return parts.count == 1 ? "1 \(noun)" : "\(parts.count) \(noun)s"
    }

    /// The question about cleaning `parts` of `item`, worded ahead: by name
    /// up to three, by count past that, largest first.
    /// - Parameters:
    ///   - result: what the scan found for the item; the question names
    ///     nothing without it.
    ///   - xcodeOpen: whether Xcode is open, which may have the project open.
    static func partsQuestion(
        _ parts: Set<ItemPart>,
        of item: Item,
        in result: ItemResult?,
        xcodeOpen: Bool,
        stage: AppModel.PendingClean.Stage) -> AppModel.PendingClean
    {
        var question = AppModel.PendingClean(items: [item], stage: stage, parts: parts)
        guard let result else { return question }
        let sorted = parts.sorted { a, b in
            let (sizeA, sizeB) = (result.kilobytes(of: a), result.kilobytes(of: b))
            return sizeA != sizeB ? sizeA > sizeB : a.sentenceName(in: result) < b.sentenceName(in: result)
        }
        if item == .derivedData, self.allProjects(parts) {
            let names = sorted.map { $0.listName(in: result) }
            let which = names.count <= 3 ? self.names(names) : "\(names.count) projects"
            question.partsSubject = "DerivedData for \(which)"
        } else if parts.count <= 3 {
            question.partsSubject = self.names(sorted.map { $0.sentenceName(in: result) })
            question.partsPlural = parts.count > 1
        } else {
            // ".build folders", "build folders": what the item's folders are called.
            let folders = result.paths.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
            question.partsSubject = item == .derivedData
                ? "\(parts.count) parts of DerivedData" : "\(parts.count) \(folders) folders"
            question.partsPlural = true
        }
        question.blockedPartNames = sorted.filter { $0.needsXcodeClosed(in: item) }.map { $0.sentenceName(in: result) }
        question.xcodeOpen = item.xcodeBuildsInto && xcodeOpen
        question.xcodeName = parts.count == 1 ? sorted[0].listName(in: result) : ""
        return question
    }

    /// Whether every part is a project's folder.
    private static func allProjects(_ parts: Set<ItemPart>) -> Bool {
        parts.allSatisfy {
            if case .folder = $0 {
                true
            } else {
                false
            }
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
