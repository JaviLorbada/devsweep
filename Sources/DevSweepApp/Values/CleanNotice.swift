import DevSweepKit
import Foundation

/// What the window says after a clean, or a put back, that left something
/// alone.
struct CleanNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    /// Xcode or Simulator didn't quit when asked, so nothing was cleaned.
    static func notQuit(_ apps: [DeveloperApp]) -> CleanNotice {
        CleanNotice(
            title: "\(apps.map(\.rawValue).joined(separator: " and ")) didn't quit",
            message: "Nothing was cleaned. Quit them yourself, for example after saving your work, and clean again.")
    }

    /// Xcode or Simulator opened after the question, so nothing was cleaned.
    static func appsOpen(_ running: Set<DeveloperApp>) -> CleanNotice {
        CleanNotice(title: "Nothing was cleaned", message: StatusText.runningApps(running))
    }

    /// A scan, or another clean, took the rows between the question and the
    /// answer, so nothing was cleaned: said, not silently dropped.
    static var rowsTaken: CleanNotice {
        CleanNotice(
            title: "Nothing was cleaned",
            message: "A scan started before you answered. Clean again once it's done.")
    }

    /// What a clean left alone, a line each; nil when it left nothing.
    static func leftAlone(_ problems: [String]) -> CleanNotice? {
        guard !problems.isEmpty else { return nil }
        return CleanNotice(title: "Some things were left alone", message: problems.joined(separator: "\n"))
    }

    /// The folders a put back couldn't move back; nil when there are none.
    static func notPutBack(_ folders: [String]) -> CleanNotice? {
        guard !folders.isEmpty else { return nil }
        return CleanNotice(
            title: "Some folders couldn't be put back",
            message: "Something now stands where they were, or the folder that held them changed. They are still "
                + "in the Trash:\n"
                + folders.joined(separator: "\n"))
    }
}
