/// Simulator devices whose runtime is gone. Listed from simctl, measured from
/// their device folders, and deleted only by `simctl delete unavailable`.
public struct SimulatorsScanner: Scanner {
    public let item = Item.simulators

    public func location(in context: ScanContext) async -> String {
        "\(context.policy.tilde("\(context.home)/Library/Developer/CoreSimulator/Devices")), runtime no longer installed"
    }

    public func collect(in context: ScanContext) async -> [String] {
        guard context.tools.simctl.isAvailable else { return [] }
        let listing = await context.tools.simctl.unavailableDevicesListing()
        return context.existing(Self.deviceIDs(in: listing).map {
            "\(context.home)/Library/Developer/CoreSimulator/Devices/\($0)"
        })
    }

    /// The last `(UDID)` on each line of `simctl list devices unavailable`.
    static func deviceIDs(in listing: String) -> [String] {
        listing.split(separator: "\n", omittingEmptySubsequences: true).compactMap { lastDeviceID(in: Array($0.utf8)) }
    }

    private static func lastDeviceID(in line: [UInt8]) -> String? {
        // Upper-case 8-4-4-4-12 hex between parentheses.
        let groups = [8, 4, 4, 4, 12]
        let length = 36
        guard line.count >= length + 2 else { return nil }
        var start = line.count - length - 2
        while start >= 0 {
            if line[start] == UInt8(ascii: "("), line[start + length + 1] == UInt8(ascii: ")") {
                var index = start + 1
                var valid = true
                for (number, size) in groups.enumerated() {
                    if number > 0 {
                        if line[index] != UInt8(ascii: "-") { valid = false; break }
                        index += 1
                    }
                    for offset in 0..<size where !isUpperHex(line[index + offset]) {
                        valid = false
                        break
                    }
                    if !valid { break }
                    index += size
                }
                if valid {
                    return String(decoding: line[(start + 1)...(start + length)], as: UTF8.self)
                }
            }
            start -= 1
        }
        return nil
    }

    private static func isUpperHex(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
    }
}
