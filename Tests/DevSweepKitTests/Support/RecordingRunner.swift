import Foundation
@testable import DevSweepKit

/// Answers every run with the same output, and keeps what it was asked.
final class RecordingRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let output: String
    private var recordedCalls: [[String]] = []
    private var recordedInputs: [Data] = []

    init(output: String) {
        self.output = output
    }

    var calls: [[String]] {
        self.lock.withLock { self.recordedCalls }
    }

    var inputs: [Data] {
        self.lock.withLock { self.recordedInputs }
    }

    func locate(_ name: String) -> String? {
        name
    }

    func run(_ name: String, _ arguments: [String], input: Data?, passthrough: Bool) async -> ProcessOutput? {
        self.lock.withLock {
            self.recordedCalls.append([name] + arguments)
            if let input {
                self.recordedInputs.append(input)
            }
        }
        return ProcessOutput(status: 0, standardOutput: Data(self.output.utf8))
    }
}
