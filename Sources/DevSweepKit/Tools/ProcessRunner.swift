import Darwin
import Foundation

public struct ProcessOutput: Sendable {
    public var status: Int32
    public var standardOutput: Data

    public init(status: Int32, standardOutput: Data = Data()) {
        self.status = status
        self.standardOutput = standardOutput
    }

    public var succeeded: Bool {
        self.status == 0
    }

    /// Standard output as text, with trailing newlines removed like `$(...)` does.
    public var text: String {
        var text = String(decoding: standardOutput, as: UTF8.self)
        while text.hasSuffix("\n") {
            text.removeLast()
        }
        return text
    }
}

/// Runs the command-line tools DevSweep depends on.
public protocol ProcessRunning: Sendable {
    /// The executable `name` resolves to through `PATH`, like `command -v`.
    func locate(_ name: String) -> String?
    /// Runs `name` found through `PATH` with standard input and error closed.
    /// With `passthrough`, its output goes to this process's standard output
    /// and error instead of being captured. Nil when it can't be found or started.
    func run(_ name: String, _ arguments: [String], passthrough: Bool) async -> ProcessOutput?
}

extension ProcessRunning {
    public func run(_ name: String, _ arguments: [String]) async -> ProcessOutput? {
        await self.run(name, arguments, passthrough: false)
    }
}

/// Runs tools found through the `PATH` of the given environment, never through
/// fixed paths, so tests can put stubs in front of `xcrun`, `brew` and the rest.
/// Children get `LC_ALL=C` so their output parses the same in every locale.
public struct LiveProcessRunner: ProcessRunning {
    public let environment: [String: String]

    public init(environment: [String: String]) {
        var environment = environment
        environment["LC_ALL"] = "C"
        self.environment = environment
    }

    public func locate(_ name: String) -> String? {
        if name.contains("/") {
            return Self.isExecutableFile(name) ? name : nil
        }
        let searchPath = self.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in searchPath.split(separator: ":", omittingEmptySubsequences: false) {
            let candidate = (directory.isEmpty ? "." : String(directory)) + "/" + name
            if Self.isExecutableFile(candidate) {
                return candidate
            }
        }
        return nil
    }

    public func run(_ name: String, _ arguments: [String], passthrough: Bool) async -> ProcessOutput? {
        guard let executable = locate(name) else { return nil }
        let environment = environment
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = environment
                process.standardInput = FileHandle.nullDevice
                let pipe = Pipe()
                if !passthrough {
                    process.standardOutput = pipe
                    process.standardError = FileHandle.nullDevice
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let data = passthrough ? Data() : pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: ProcessOutput(status: process.terminationStatus, standardOutput: data))
            }
        }
    }

    private static func isExecutableFile(_ path: String) -> Bool {
        FileSystem.isRegularFile(path) && access(path, X_OK) == 0
    }
}
