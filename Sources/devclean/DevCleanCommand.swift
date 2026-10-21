import ArgumentParser
import Darwin
import DevCleanKit
import Foundation

@main
struct DevCleanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "devclean",
        abstract: "Shows how much space developer caches take up. With --run, deletes them.",
        helpNames: []
    )

    @Flag(name: .customLong("run"), help: "Delete the items in the report (asks first)")
    var run = false

    @Flag(name: [.customShort("y"), .customLong("yes")], help: "Don't ask for confirmation (with --run)")
    var yes = false

    @Option(name: .customLong("skip"), parsing: .unconditional, help: "Comma-separated items to leave alone")
    var skip: String?

    @Option(name: .customLong("projects"), parsing: .unconditional, help: "Colon-separated folders to search for build folders")
    var projects: String?

    /// The bash script's argument rules run first, so its exact errors, help
    /// text and exit codes survive; the parser then reads what they let through.
    static func main() async {
        // Numbers like "1.5GB" parse and print the same in every locale, in
        // this process and in every tool it runs.
        setenv("LC_ALL", "C", 1)
        setlocale(LC_ALL, "C")
        let terminal = StandardTerminal()

        switch CommandLineOptions.check(Array(CommandLine.arguments.dropFirst())) {
        case .help:
            terminal.write(CommandLineOptions.usage)
            Darwin.exit(0)
        case .failure(let message):
            terminal.warn(message)
            Darwin.exit(1)
        case .options(let options):
            do {
                var command = try parse(options.arguments)
                try await command.run()
            } catch {
                terminal.warn(fullMessage(for: error))
                Darwin.exit(1)
            }
        }
    }

    mutating func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        let status = await CommandLineSession.run(
            CommandLineOptions(run: run, yes: yes, skip: skip, projects: projects),
            environment: environment,
            tools: .live(environment: environment, passthroughOutput: true),
            terminal: StandardTerminal()
        )
        Darwin.exit(status)
    }
}
