/// Device Support folders older than the newest version for their OS and
/// device model. Xcode copies them again when a device on that version connects.
public struct DeviceSupportScanner: Scanner {
    public let item = Item.deviceSupport

    static let systems = ["iOS", "watchOS", "tvOS", "visionOS", "macOS"]

    public func location(in context: ScanContext) async -> String {
        "\(context.policy.tilde("\(context.home)/Library/Developer/Xcode"))/<OS> DeviceSupport, all but the newest per device model"
    }

    public func collect(in context: ScanContext) async -> [String] {
        var entries: [Entry] = []
        for system in Self.systems {
            let folder = "\(context.home)/Library/Developer/Xcode/\(system) DeviceSupport"
            for name in context.files.globNames(folder) {
                let path = "\(folder)/\(name)"
                guard context.files.isDirectory(path), !context.files.isSymlink(path) else { continue }
                entries.append(Entry(system: system, name: name, modified: context.files.modificationTime(path), path: path))
            }
        }
        return context.existing(Self.old(entries))
    }

    struct Entry: Sendable {
        let system: String
        let name: String
        let modified: Int
        let path: String
    }

    /// Paths of entries older than the newest version of their group. Ties on
    /// version go to the most recently modified build, and every folder of the
    /// kept version and build stays (like an arm64e copy). Names that don't
    /// parse are never listed.
    static func old(_ entries: [Entry]) -> [String] {
        struct Parsed {
            let group: String
            let id: String
            let rank: String
            let path: String
        }
        var parsed: [Parsed] = []
        var best: [String: (rank: String, id: String)] = [:]

        for entry in entries {
            // A tab or newline would have broken the script's rows; keep such folders.
            if entry.name.contains("\t") || entry.name.contains("\n") { continue }
            let tokens = entry.name.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
            guard let first = tokens.first else { continue }
            let device: String
            let version: String
            let build: String
            if isVersion(first) {
                device = ""
                version = first
                build = tokens.count > 1 ? tokens[1] : ""
            } else if tokens.count >= 2, isVersion(tokens[1]) {
                device = first
                version = tokens[1]
                build = tokens.count > 2 ? tokens[2] : ""
            } else {
                continue
            }
            if !build.isEmpty, !(build.hasPrefix("(") && build.hasSuffix(")") && build.count > 2) { continue }

            let parts = version.split(separator: ".").map { Int($0) ?? Int.max }
            func part(_ index: Int) -> Int { index < parts.count ? parts[index] : 0 }
            let rank = "v" + padded(part(0), 6) + padded(part(1), 6) + padded(part(2), 6) + padded(part(3), 6)
                + padded(entry.modified, 12)
            let group = entry.system + "\u{1C}" + device
            let id = "\(version) \(build)"
            parsed.append(Parsed(group: group, id: id, rank: rank, path: entry.path))
            // Only a strictly higher rank replaces the one kept so far.
            if let current = best[group], !current.rank.utf8.lexicographicallyPrecedes(rank.utf8) {
                continue
            }
            best[group] = (rank, id)
        }
        return parsed.filter { $0.id != best[$0.group]?.id }.map(\.path)
    }

    /// `^[0-9]+(\.[0-9]+)*$`
    static func isVersion(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }
    }

    /// `%0Nd`
    private static func padded(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
    }
}
