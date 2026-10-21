import Darwin

/// Where a command line session reads and writes.
public protocol Terminal: Sendable {
    func write(_ text: String)
    /// Writes a warning line as `devclean: message`.
    func warn(_ message: String)
    func readLine() -> String?
    /// Standard input is a terminal someone can answer from.
    var inputIsInteractive: Bool { get }
    /// Standard output is a terminal, so dim text shows.
    var outputIsInteractive: Bool { get }
}

/// The bash script's `main`, from preflight to "Done.", returning its exit status.
public enum CommandLineSession {
    public static func run(
        _ options: CommandLineOptions,
        environment: [String: String],
        tools: Tools,
        terminal: any Terminal,
        effectiveUserID: uid_t = geteuid()
    ) async -> Int32 {
        let engine: Engine
        do {
            // The script's preflight order: root and HOME first, then --skip.
            _ = try PathPolicy.preflight(home: environment["HOME"] ?? "", effectiveUserID: effectiveUserID)
            let skipped = try ScanConfig.parseSkip(options.skip ?? "")
            let config = ScanConfig.fromEnvironment(
                environment,
                projects: options.projects,
                skipped: skipped,
                includeExtras: !options.run
            )
            engine = try Engine(config: config, tools: tools, effectiveUserID: effectiveUserID)
        } catch {
            terminal.warn(error.description)
            return 1
        }

        if options.run, !engine.config.skipsEverythingXcodeUses {
            for app in DeveloperApp.allCases where await tools.runningApps.isRunning(app) {
                terminal.warn("Quit \(app.rawValue) first, then run devclean --run again.")
                return 1
            }
        }

        let style: ReportStyle = terminal.outputIsInteractive && (environment["NO_COLOR"] ?? "").isEmpty
            ? .terminal : .plain
        terminal.write(Report.scanning)

        var found: [ItemResult] = []
        for await event in engine.scan() {
            switch event {
            case .projectFolders(let folders):
                terminal.write(Report.projectFolders(folders))
            case .warning(let message):
                terminal.warn(message)
            case .finished(let result):
                if !result.isEmpty { found.append(result) }
                terminal.write(Report.row(result, style: style))
            case .done(let totalBytes, let freeBytes):
                terminal.write(Report.summary(
                    totalKilobytes: found.isEmpty ? nil : totalBytes / 1024,
                    freeKilobytes: freeBytes / 1024
                ))
            case .extras(let extras):
                terminal.write(Report.extras(extras, staleDays: engine.config.staleDays, policy: engine.policy, style: style))
            case .started, .progress:
                break
            }
        }

        guard options.run else {
            terminal.write(Report.closing(foundAnything: !found.isEmpty))
            return 0
        }
        guard !found.isEmpty else {
            terminal.write(Report.closing(foundAnything: false))
            return 0
        }

        if !options.yes {
            guard terminal.inputIsInteractive else {
                terminal.warn("Not deleting without confirmation. Add --yes to confirm.")
                return 1
            }
            terminal.write(Report.confirmation(totalKilobytes: found.reduce(0) { $0 + $1.kilobytes }))
            let answer = (terminal.readLine() ?? "").trimmingIFSWhitespace()
            guard ["y", "Y", "yes", "YES"].contains(answer) else {
                terminal.write("Nothing deleted.\n")
                return 0
            }
        }

        let before = engine.diskSpace()?.availableKilobytes ?? 0
        for result in found {
            terminal.write(Report.deleting(result))
            let outcome = await engine.clean(result, mode: .delete)
            outcome.warnings.forEach(terminal.warn)
        }
        terminal.write(Report.done(freeBefore: before, freeAfter: engine.diskSpace()?.availableKilobytes ?? 0))
        return 0
    }
}

extension String {
    /// What `read -r` leaves of a line: leading and trailing spaces, tabs and newlines removed.
    func trimmingIFSWhitespace() -> String {
        let isBlank: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\n" }
        return String(drop(while: isBlank).reversed().drop(while: isBlank).reversed())
    }
}

/// Standard input, output and error, unbuffered, so lines from devclean and
/// from the tools it runs arrive in the order they were written.
public struct StandardTerminal: Terminal {
    public init() {}

    public func write(_ text: String) {
        Self.write(STDOUT_FILENO, text)
    }

    public func warn(_ message: String) {
        Self.write(STDERR_FILENO, "devclean: \(message)\n")
    }

    public func readLine() -> String? {
        Swift.readLine(strippingNewline: true)
    }

    public var inputIsInteractive: Bool { isatty(STDIN_FILENO) != 0 }
    public var outputIsInteractive: Bool { isatty(STDOUT_FILENO) != 0 }

    private static func write(_ descriptor: Int32, _ text: String) {
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBufferPointer {
                Darwin.write(descriptor, $0.baseAddress, $0.count)
            }
            if written < 0, errno == EINTR { continue }
            if written <= 0 { return }
            offset += written
        }
    }
}
