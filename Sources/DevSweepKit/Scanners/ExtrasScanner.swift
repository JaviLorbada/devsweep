import Foundation

/// Installed Xcodes, simulator runtimes and, when the config asks, git
/// worktrees. Listed, never deleted by a scan.
enum ExtrasScanner {
    static func scan(in context: ScanContext) async -> Extras {
        await Extras(
            xcodes: self.xcodes(in: context),
            runtimes: self.runtimes(in: context),
            worktrees: context.config.includeWorktrees ? WorktreeScanner.scan(in: context) : [])
    }

    // MARK: Xcodes

    static func xcodes(in context: ScanContext) async -> [InstalledXcode] {
        var selected = await context.tools.xcodeSelect.selectedDeveloperDirectory()
        selected = selected.removingSuffix("/Contents/Developer")
        let selectedReal = selected.isEmpty ? nil : FileSystem.physicalDirectory(selected)

        var result: [InstalledXcode] = []
        for directory in context.config.applicationsDirectories where !directory.isEmpty {
            let folder = context.policy.expandTilde(directory)
            for name in context.files.globNames(folder) where FileSystem.matches(name, pattern: "Xcode*.app") {
                let app = "\(folder)/\(name)"
                guard context.files.isDirectory(app), !context.files.isSymlink(app) else { continue }
                let isSelected = selectedReal
                    .map { FileSystem.physicalDirectory(app)?.bytesEqual($0) ?? false } ?? false
                result.append(InstalledXcode(
                    path: app,
                    version: PropertyList
                        .string(at: "\(app)/Contents/Info.plist", key: "CFBundleShortVersionString") ?? "?",
                    build: PropertyList.string(at: "\(app)/Contents/version.plist", key: "ProductBuildVersion") ?? "?",
                    kilobytes: context.measurer.measure(app).kilobytes,
                    lastOpened: context.tools.lastUsedDates.lastUsedDate(of: app),
                    isSelected: isSelected))
            }
        }
        return result
    }

    // MARK: Runtimes

    static func runtimes(in context: ScanContext) async -> [SimulatorRuntime] {
        await self.runtimes(in: context, now: context.clock.now())
    }

    static func runtimes(in context: ScanContext, now: Date) async -> [SimulatorRuntime] {
        let simctl = context.tools.simctl
        guard simctl.isAvailable, let runtimesData = await simctl.runtimesJSON(),
              !runtimesData.isEmpty else { return [] }
        let list = SimctlRuntimeList(runtimesData)
        let devices = await SimctlDeviceList(simctl.devicesJSON() ?? Data())
        let downloads = self.downloads(list)
        return self.runtimes(list, devices: devices, now: now).map { runtime in
            guard let folder = downloads[runtime.id] else { return runtime }
            let kilobytes = context.measurer.measure(folder).kilobytes
            return kilobytes > 0 ? runtime.counting(downloadKilobytes: kilobytes) : runtime
        }
    }

    /// The download macOS keeps for each runtime that has one of its own, by
    /// runtime id: the MobileAsset folder simctl's `parentImagePath` is in,
    /// which `simctl runtime delete` removes with the runtime. simctl's size
    /// leaves it out. Not counted, as the bash script decides: a folder that
    /// holds any runtime's own files, this one's included, which `sizeBytes`
    /// already counts, and one several runtimes name, which removing one of
    /// them doesn't free.
    static func downloads(_ list: SimctlRuntimeList) -> [String: String] {
        var parents: [String: String] = [:]
        for (id, runtime) in list.runtimes {
            parents[id] = runtime.parentImagePath.flatMap(self.assetFolder)
        }
        let namedBy = Dictionary(grouping: parents.values) { $0 }.mapValues(\.count)
        let paths = list.runtimes.map { $0.runtime.path ?? "" }
        return parents.filter { _, folder in
            let inside = Array((folder + "/").utf8)
            return namedBy[folder] == 1
                && !paths.contains { $0.utf8.elementsEqual(folder.utf8) || $0.utf8.starts(with: inside) }
        }
    }

    /// The `.asset` folder a path is in, as the script's `/^(.*\.asset)(\/|$)/`
    /// finds it: up to the last `.asset` that ends the path or a folder's
    /// name, on the path's first line. Nil when there is none.
    static func assetFolder(_ path: String) -> String? {
        let bytes = Array(path.utf8)
        let marker = Array(".asset".utf8)
        // JavaScript's `.` stops at a line break: \n, \r, U+2028 or U+2029.
        let lineEnd = bytes.indices.first { index in
            bytes[index] == 0x0A || bytes[index] == 0x0D
                || (bytes[index...].starts(with: [0xE2, 0x80]) && index + 2 < bytes.count
                    && (bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9))
        } ?? bytes.count
        let ends = (0..<max(0, lineEnd - marker.count + 1)).map { $0 + marker.count }.filter { end in
            bytes[(end - marker.count)..<end].elementsEqual(marker) && (end == bytes.count || bytes[end] == 0x2F)
        }
        return ends.last.map { String(decoding: bytes[..<$0], as: UTF8.self) }
    }

    /// Joins `simctl runtime list -j` with `simctl list devices -j`, sorted by
    /// platform, then newest version first.
    static func runtimes(_ list: SimctlRuntimeList, devices: SimctlDeviceList, now: Date) -> [SimulatorRuntime] {
        let parsed = list.runtimes.map { id, runtime in
            let identifier = runtime.runtimeIdentifier ?? ""
            return SimulatorRuntime(
                id: id,
                identifier: identifier,
                platform: self.platform(of: identifier),
                version: runtime.version ?? "?",
                build: runtime.build ?? "?",
                kilobytes: Int64(((runtime.sizeBytes ?? 0) / 1024 + 0.5).rounded(.down)),
                lastUsedDay: runtime.lastUsedAt.flatMap { $0.isEmpty ? nil : String($0.prefix(10)) },
                daysSinceUsed: runtime.lastUsedAt.flatMap { JavaScriptDate.parse($0) }.map {
                    Int(((now.timeIntervalSince1970 * 1000 - $0) / 86_400_000).rounded(.down))
                },
                simulatorCount: devices.count(for: identifier))
        }
        // A stable sort, like JavaScript's.
        return parsed.enumerated().sorted { a, b in
            let platform = a.element.platform.caseInsensitiveCompare(b.element.platform)
            if platform != .orderedSame { return platform == .orderedAscending }
            let version = b.element.version.compare(a.element.version, options: .numeric)
            if version != .orderedSame { return version == .orderedAscending }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// "iOS" from "com.apple.CoreSimulator.SimRuntime.iOS-27-0".
    static func platform(of identifier: String) -> String {
        var rest = Substring(identifier)
        if let marker = identifier.range(of: "SimRuntime.", options: .backwards) {
            rest = identifier[marker.upperBound...]
        }
        return String(rest.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }
}

/// The order of an object's keys in JSON text, which decoding it into a dictionary loses.
enum JSONKeyOrder {
    static func topLevelKeys(_ data: Data) -> [String] {
        let bytes = [UInt8](data)
        var keys: [String] = []
        var depth = 0
        var index = 0
        var expectingKey = false
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                expectingKey = byte == UInt8(ascii: "{") && depth == 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
            case UInt8(ascii: ","):
                expectingKey = depth == 1
            case UInt8(ascii: "\""):
                let start = index
                index += 1
                while index < bytes.count, bytes[index] != UInt8(ascii: "\"") {
                    if bytes[index] == UInt8(ascii: "\\") { index += 1 }
                    index += 1
                }
                if expectingKey, depth == 1,
                   let key = try? JSONSerialization.jsonObject(
                       with: Data(bytes[start...min(index, bytes.count - 1)]),
                       options: .fragmentsAllowed) as? String
                {
                    keys.append(key)
                }
                expectingKey = false
            default:
                break
            }
            index += 1
        }
        return keys
    }
}

/// The ISO 8601 forms of JavaScript's `Date.parse`, in milliseconds. Date-time
/// forms without an offset are local time; date-only forms are UTC.
enum JavaScriptDate {
    static func parse(_ text: String) -> Double? {
        // swiftlint:disable:next line_length
        let pattern = #/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?(Z|[+-]\d{2}:\d{2})?)?$/#
        guard let match = text.wholeMatch(of: pattern) else { return nil }
        var parts = DateComponents()
        parts.year = Int(match.1)
        parts.month = Int(match.2)
        parts.day = Int(match.3)
        parts.hour = match.4.flatMap { Int($0) } ?? 0
        parts.minute = match.5.flatMap { Int($0) } ?? 0
        parts.second = match.6.flatMap { Int($0) } ?? 0

        var calendar = Calendar(identifier: .gregorian)
        if match.4 == nil {
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        } else if let zone = match.8 {
            if zone == "Z" {
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            } else {
                let sign = zone.hasPrefix("-") ? -1 : 1
                let hours = Int(zone.dropFirst().prefix(2)) ?? 0
                let minutes = Int(zone.suffix(2)) ?? 0
                guard let offset = TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60)) else { return nil }
                calendar.timeZone = offset
            }
        } else {
            calendar.timeZone = .current
        }
        guard let date = calendar.date(from: parts) else { return nil }
        var milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        if let fraction = match.7 {
            milliseconds += Double(String(fraction.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
        }
        return milliseconds
    }
}
