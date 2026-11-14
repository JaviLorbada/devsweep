import Foundation

// What simctl prints as JSON, decoded once into typed values. Read leniently,
// as the bash script's JavaScript reads it: a runtime that isn't an object is
// left out, and a field of another type counts as missing.

/// `simctl runtime list -j`: each runtime with its id, in the order the JSON
/// lists them.
struct SimctlRuntimeList: Sendable {
    struct Runtime: Decodable, Sendable {
        var runtimeIdentifier: String?
        /// As JavaScript's `value || '?'` would print it, nil when it would
        /// print `?`.
        var version: String?
        var build: String?
        var sizeBytes: Double?
        var lastUsedAt: String?
        /// The image simctl mounts.
        var path: String?
        /// The download macOS keeps apart for a runtime it copied elsewhere.
        var parentImagePath: String?

        private enum Field: String, CodingKey {
            case runtimeIdentifier, version, build, sizeBytes, lastUsedAt, path, parentImagePath
        }

        init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: Field.self)
            self.runtimeIdentifier = fields.value(String.self, .runtimeIdentifier)
            self.version = fields.text(.version)
            self.build = fields.text(.build)
            self.sizeBytes = fields.value(Double.self, .sizeBytes)
            self.lastUsedAt = fields.value(String.self, .lastUsedAt)
            self.path = fields.value(String.self, .path)
            self.parentImagePath = fields.value(String.self, .parentImagePath)
        }
    }

    let runtimes: [(id: String, runtime: Runtime)]

    /// Empty when the JSON isn't an object of runtimes.
    init(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode([String: Lossy<Runtime>].self, from: data) else {
            self.runtimes = []
            return
        }
        let order = JSONKeyOrder.topLevelKeys(data)
        let ids = order.filter { decoded[$0] != nil } + decoded.keys.filter { !order.contains($0) }.sortedBytewise()
        self.runtimes = ids.compactMap { id in decoded[id]?.value.map { (id, $0) } }
    }
}

/// `simctl list devices -j`: how many simulators each runtime has.
struct SimctlDeviceList: Sendable {
    private let counts: [String: Int]

    private struct Devices: Decodable {
        var devices: [String: Lossy<[Ignored]>]?
    }

    /// A simulator, counted and not read.
    private struct Ignored: Decodable {
        init(from _: any Decoder) {}
    }

    /// None when the JSON isn't the device list.
    init(_ data: Data) {
        let devices = (try? JSONDecoder().decode(Devices.self, from: data))?.devices ?? [:]
        self.counts = devices.compactMapValues { $0.value?.count }
    }

    /// Simulators for the runtime with this identifier.
    func count(for runtimeIdentifier: String) -> Int {
        self.counts[runtimeIdentifier] ?? 0
    }
}

/// A value decoded when it can be, nil otherwise, so that one odd entry
/// doesn't lose the others.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        self.value = try? Value(from: decoder)
    }
}

extension Lossy: Sendable where Value: Sendable {}

extension KeyedDecodingContainer {
    /// The field, nil when it is missing or of another type.
    fileprivate func value<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        try? self.decodeIfPresent(type, forKey: key)
    }

    /// A string or a number as JavaScript's `value || '?'` prints it, nil
    /// when it would print `?`: empty, zero, missing or of another type.
    fileprivate func text(_ key: Key) -> String? {
        if let string = self.value(String.self, key) { return string.isEmpty ? nil : string }
        if let number = self.value(Double.self, key) { return number == 0 ? nil : NSNumber(value: number).stringValue }
        return nil
    }
}
