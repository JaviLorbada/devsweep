import Foundation

/// Dim text in a terminal, nothing otherwise.
public struct ReportStyle: Sendable, Equatable {
    public var dim: String
    public var reset: String

    public static let plain = ReportStyle(dim: "", reset: "")
    public static let terminal = ReportStyle(dim: "\u{1B}[2m", reset: "\u{1B}[0m")
}

/// The text report, byte for byte what `bin/devclean` prints. Every function
/// returns whole lines, each ending in a newline.
///
/// Widths count bytes, as `printf` does under `LC_ALL=C`.
public enum Report {
    public static let separator = "------------------------------------------------------------------"

    /// `>= 1 GiB` as `%.1f GB`, `>= 1 MiB` as `%d MB`, else `%d KB`.
    public static func human(kilobytes: Int64) -> String {
        if kilobytes >= 1_048_576 {
            return String(format: "%.1f GB", Double(kilobytes) / 1_048_576)
        }
        if kilobytes >= 1024 {
            return "\(kilobytes / 1024) MB"
        }
        return "\(kilobytes) KB"
    }

    public static func human(bytes: Int64) -> String {
        self.human(kilobytes: bytes / 1024)
    }

    public static let scanning = "Scanning developer caches. Big ones can take a minute...\n"

    /// Which project folders get searched and which don't exist, then a blank line.
    public static func projectFolders(_ folders: ProjectFolders, command: CommandName = .product) -> String {
        let found = folders.found.joined(separator: ", ")
        let missing = folders.missing.joined(separator: ", ")
        let outside = folders.outside.joined(separator: ", ")

        var details: String = if found.isEmpty {
            missing.isEmpty ? "" : "looked for \(missing)"
        } else {
            missing.isEmpty ? "" : "not found: \(missing)"
        }
        if !outside.isEmpty {
            details = (details.isEmpty ? "" : "\(details); ") + "outside your home folder, skipped: \(outside)"
        }
        let suffix = details.isEmpty ? "" : " (\(details))"

        if found.isEmpty {
            return "Project folders: none found\(suffix).\n"
                + "Use --projects or \(command.variable("PROJECT_DIRS")) to say where your code lives.\n\n"
        }
        return "Project folders: \(found)\(suffix)\n\n"
    }

    /// An item's row, the dim line saying where it looks, and for DerivedData the breakdown.
    public static func row(_ result: ItemResult, style: ReportStyle = .plain) -> String {
        let size = result.isEmpty ? "none" : self.human(kilobytes: result.kilobytes)
        var text = "  \(left(result.item.rawValue, 16)) \(self.left(result.label, 38)) \(self.right(size, 10))\n"
        text += "  \(self.left("", 16)) \(style.dim)\(result.location)\(style.reset)\n"
        if let breakdown = result.derivedData, !result.isEmpty {
            text += self.derivedData(breakdown, style: style)
        }
        return text
    }

    /// The shared caches first, then the five biggest project folders and a
    /// summary of the rest.
    public static func derivedData(_ breakdown: DerivedDataBreakdown, style: ReportStyle = .plain) -> String {
        let indent = String(repeating: " ", count: 21)
        func part(_ name: String, _ kilobytes: Int64) -> String {
            "\(indent)\(self.left(name, 38)) \(self.right(self.human(kilobytes: kilobytes), 8))\n"
        }

        var text = ""
        if breakdown.compilationCacheKilobytes > 0 {
            text += part("Compilation cache, all projects", breakdown.compilationCacheKilobytes)
        }
        if breakdown.moduleCacheKilobytes > 0 {
            text += part("Module cache, all projects", breakdown.moduleCacheKilobytes)
        }
        for project in breakdown.projects.prefix(5) {
            text += "\(indent)\(self.left(project.name.prefixBytes(21), 21)) \(self.left(project.statusText, 16)) "
                + "\(self.right(self.human(kilobytes: project.kilobytes), 8))\n"
        }
        let rest = breakdown.projects.dropFirst(5)
        let restKilobytes = rest.reduce(0) { $0 + $1.kilobytes }
        if rest.count > 1 {
            text += part("\(rest.count) more projects", restKilobytes)
        } else if rest.count == 1 {
            text += part("1 more project", restKilobytes)
        }
        if breakdown.otherKilobytes > 0 {
            text += part("Other", breakdown.otherKilobytes)
        }
        text += "  \(self.left("", 16)) \(style.dim)Each part comes back as you build; projects you no longer build "
            + "stay gone.\(style.reset)\n"
        return text
    }

    /// The separator, Total, Free space now, and a blank line.
    /// - Parameter totalKilobytes: nil when nothing was found.
    public static func summary(totalKilobytes: Int64?, freeKilobytes: Int64) -> String {
        "  \(self.separator)\n"
            + "  \(self.left("Total", 55)) "
            + "\(self.right(totalKilobytes.map { self.human(kilobytes: $0) } ?? "none", 10))\n"
            + "  \(self.left("Free space now", 55)) \(self.right(self.human(kilobytes: freeKilobytes), 10))\n"
            + "\n"
    }

    /// Installed Xcodes and simulator runtimes, which the tool never deletes.
    public static func extras(
        _ extras: Extras,
        staleDays: Int,
        policy: PathPolicy,
        style: ReportStyle = .plain,
        command: CommandName = .product) -> String
    {
        var text = "Also worth a look. \(command.name) never deletes these:\n\n"

        text += "Xcode versions\n"
        for xcode in extras.xcodes {
            text += "  \(self.left(xcode.title, 24)) \(self.right(self.human(kilobytes: xcode.kilobytes), 10))   "
                + "\(xcode.note)\n"
            text += "    \(style.dim)\(policy.tilde(xcode.path))\(style.reset)\n"
        }
        if extras.xcodes.isEmpty {
            text += "  None found.\n"
        } else if extras.xcodes.count > 1 {
            text += "  Each Xcode keeps its own compilation cache in DerivedData. To remove\n"
            text += "  one you no longer need, quit it and move it to the Trash.\n"
        }
        text += "\n"

        text += "Simulator runtimes\n"
        var flagged = 0
        for runtime in extras.runtimes {
            text += "  \(self.left(runtime.title, 24)) \(self.right(self.human(kilobytes: runtime.kilobytes), 10))   "
                + "\(runtime.note)\n"
            if let reason = runtime.flagReason(staleDays: staleDays) {
                flagged += 1
                text += "    \(style.dim)\(reason). Remove with: \(runtime.removalCommand)\(style.reset)\n"
            }
        }
        if extras.runtimes.isEmpty {
            text += "  None found.\n"
        } else if flagged == 0 {
            text += "  None look unused. To remove one anyway: Xcode > Settings > Components.\n"
        }
        text += "\n"
        // Never under the original script's name, whose report has no such section.
        if command == .product {
            text += self.worktrees(extras.worktrees, policy: policy, style: style)
        }
        return text
    }

    /// The git worktrees of the repositories in the project folders, with the
    /// command that removes each one with nothing in it to lose.
    static func worktrees(_ worktrees: [GitWorktree], policy: PathPolicy, style: ReportStyle) -> String {
        var text = "Git worktrees\n"
        for worktree in worktrees {
            text += "  \(self.left(worktree.name, 24)) \(self.right(self.human(kilobytes: worktree.kilobytes), 10))   "
                + "\(worktree.note)\n"
            if let kept = worktree.keptBecause {
                text += "    \(style.dim)\(kept), so it stays.\(style.reset)\n"
            } else {
                text += "    \(style.dim)Nothing to lose. Remove with: "
                    + "\(worktree.removalCommand(policy: policy))\(style.reset)\n"
            }
        }
        if worktrees.isEmpty {
            text += "  None found in the project folders' repositories.\n"
        }
        text += "\n"
        return text
    }

    /// The last line of a report that deleted nothing.
    public static func closing(foundAnything: Bool, command: CommandName = .product) -> String {
        foundAnything
            ? "Nothing deleted. Run '\(command.name) --run' to delete the caches in the first list.\n"
            : "Nothing to clean.\n"
    }

    public static func confirmation(totalKilobytes: Int64) -> String {
        "Delete \(self.human(kilobytes: totalKilobytes))? [y/N] "
    }

    public static func deleting(_ result: ItemResult) -> String {
        "  Deleting \(result.label)...\n"
    }

    public static func done(freeBefore: Int64, freeAfter: Int64) -> String {
        "\nDone. Free space: \(self.human(kilobytes: freeBefore)) -> \(self.human(kilobytes: freeAfter))\n"
    }

    // MARK: Padding

    /// `%-Ns`
    static func left(_ text: String, _ width: Int) -> String {
        let count = text.utf8.count
        return count >= width ? text : text + String(repeating: " ", count: width - count)
    }

    /// `%Ns`
    static func right(_ text: String, _ width: Int) -> String {
        let count = text.utf8.count
        return count >= width ? text : String(repeating: " ", count: width - count) + text
    }
}
