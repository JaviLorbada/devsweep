import Foundation

/// Installed Xcodes and simulator runtimes. Listed, never deleted by a scan.
enum ExtrasScanner {
    static func scan(in context: ScanContext) async -> Extras {
        Extras(xcodes: await xcodes(in: context), runtimes: await runtimes(in: context))
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
                let isSelected = selectedReal.map { FileSystem.physicalDirectory(app)?.bytesEqual($0) ?? false } ?? false
                result.append(InstalledXcode(
                    path: app,
                    version: PropertyList.string(at: "\(app)/Contents/Info.plist", key: "CFBundleShortVersionString") ?? "?",
                    build: PropertyList.string(at: "\(app)/Contents/version.plist", key: "ProductBuildVersion") ?? "?",
                    kilobytes: context.measurer.measure(app).kilobytes,
                    lastOpened: context.tools.lastUsedDates.lastUsedDate(of: app),
                    isSelected: isSelected
                ))
            }
        }
        return result
    }

    // MARK: Runtimes

    static func runtimes(in context: ScanContext) async -> [SimulatorRuntime] {
        await runtimes(in: context, now: context.clock.now())
    }

    static func runtimes(in context: ScanContext, now: Date) async -> [SimulatorRuntime] {
        let simctl = context.tools.simctl
        guard simctl.isAvailable, let runtimesData = await simctl.runtimesJSON(), !runtimesData.isEmpty else { return [] }
        let devicesData = await simctl.devicesJSON() ?? Data()
        return parseRuntimes(runtimesData, devices: devicesData, now: now)
    }

    /// Joins `simctl runtime list -j` with `simctl list devices -j`, sorted by
    /// platform, then newest version first.
    static func parseRuntimes(_ runtimesData: Data, devices devicesData: Data, now: Date) -> [SimulatorRuntime] {
        guard let runtimes = (try? JSONSerialization.jsonObject(with: runtimesData)) as? [String: Any] else { return [] }
        let devicesObject = (try? JSONSerialization.jsonObject(with: devicesData)) as? [String: Any]
        let devices = devicesObject?["devices"] as? [String: Any] ?? [:]

        let order = JSONKeyOrder.topLevelKeys(runtimesData)
        let ids = order.filter { runtimes[$0] != nil } + runtimes.keys.filter { !order.contains($0) }.sortedBytewise()

        let parsed: [SimulatorRuntime] = ids.compactMap { id in
            guard let runtime = runtimes[id] as? [String: Any] else { return nil }
            let identifier = runtime["runtimeIdentifier"] as? String ?? ""
            let lastUsedAt = runtime["lastUsedAt"] as? String
            let size = (runtime["sizeBytes"] as? NSNumber)?.doubleValue ?? 0
            return SimulatorRuntime(
                id: id,
                identifier: identifier,
                platform: platform(of: identifier),
                version: text(runtime["version"]) ?? "?",
                build: text(runtime["build"]) ?? "?",
                kilobytes: Int64((size / 1024 + 0.5).rounded(.down)),
                lastUsedDay: lastUsedAt.flatMap { $0.isEmpty ? nil : String($0.prefix(10)) },
                daysSinceUsed: lastUsedAt.flatMap { JavaScriptDate.parse($0) }.map {
                    Int(((now.timeIntervalSince1970 * 1000 - $0) / 86_400_000).rounded(.down))
                },
                simulatorCount: (devices[identifier] as? [Any])?.count ?? 0
            )
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

    /// A JSON value as JavaScript's `value || '?'` would print it, nil for empty or missing.
    private static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String: string.isEmpty ? nil : string
        case let number as NSNumber: number == 0 ? nil : number.stringValue
        default: nil
        }
    }
}

/// The order of an object's keys in JSON text, which `JSONSerialization` loses.
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
                   let key = try? JSONSerialization.jsonObject(with: Data(bytes[start...min(index, bytes.count - 1)]), options: .fragmentsAllowed) as? String {
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
