/// Old Homebrew versions and downloads. Brew measures and deletes them itself.
public struct HomebrewScanner: Scanner {
    public let item = Item.homebrew

    public func location(in context: ScanContext) async -> String {
        context.tools.brew.isAvailable ? "brew cleanup --prune=all" : "Homebrew not installed"
    }

    public func collect(in context: ScanContext) async -> [String] {
        []
    }

    public func scan(in context: ScanContext, progress: @escaping @Sendable (Int64) -> Void) async -> ItemResult {
        var kilobytes: Int64 = 0
        if context.tools.brew.isAvailable {
            kilobytes = await Self.kilobytes(fromDryRun: context.tools.brew.cleanupDryRun())
        }
        progress(kilobytes * 1024)
        return await ItemResult(item: self.item, paths: [], kilobytes: kilobytes, location: self.location(in: context))
    }

    /// Size in KB from the dry run's "would free approximately 1.5GB" line.
    /// The last such line wins; units are binary multiples; fractions of a KB
    /// are dropped.
    static func kilobytes(fromDryRun output: String) -> Int64 {
        var result: Double = 0
        for line in output.split(separator: "\n", omittingEmptySubsequences: false)
            where line.contains("would free approximately")
        {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            var value = ""
            for (index, field) in fields.enumerated() where field == "approximately" {
                value = index + 1 < fields.count ? String(fields[index + 1]) : ""
            }
            let unit = String(value.drop(while: { $0.isASCII && ($0.isNumber || $0 == ".") }))
            let multiplier: Double = switch unit {
            case "B": 1.0 / 1024
            case "KB": 1
            case "MB": 1024
            case "GB": 1_048_576
            case "TB": 1_073_741_824
            default: 0
            }
            result = leadingNumber(value) * multiplier
        }
        guard result.isFinite, result > 0, result < Double(Int64.max) else { return 0 }
        return Int64(result)
    }

    /// The number at the start of `text`, like awk's `text + 0`.
    static func leadingNumber(_ text: String) -> Double {
        var scalars = Substring(text).unicodeScalars.drop(while: { $0 == " " || $0 == "\t" })
        var negative = false
        if let sign = scalars.first, sign == "+" || sign == "-" {
            negative = sign == "-"
            scalars = scalars.dropFirst()
        }
        let whole = String(String.UnicodeScalarView(scalars.prefix(while: { ("0"..."9").contains($0) })))
        scalars = scalars.dropFirst(whole.unicodeScalars.count)
        var fraction = ""
        if scalars.first == "." {
            fraction = String(String.UnicodeScalarView(scalars.dropFirst().prefix(while: { ("0"..."9").contains($0) })))
        }
        guard !whole.isEmpty || !fraction.isEmpty else { return 0 }
        let value = Double("\(whole.isEmpty ? "0" : whole).\(fraction.isEmpty ? "0" : fraction)") ?? 0
        return negative ? -value : value
    }
}
