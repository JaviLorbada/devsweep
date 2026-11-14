import ArgumentParser
import Darwin
import DevSweepKit
import Foundation

@main
struct DevSweepCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: ProductInfo.cliName,
        abstract: "Shows how much space developer caches take up. With --run, deletes them.",
        helpNames: [])

    @Flag(name: .customLong("run"), help: "Delete the items in the report (asks first)")
    var run = false

    @Flag(name: [.customShort("y"), .customLong("yes")], help: "Don't ask for confirmation (with --run)")
    var yes = false

    @Option(name: .customLong("skip"), parsing: .unconditional, help: "Comma-separated items to leave alone")
    var skip: String?

    @Option(
        name: .customLong("projects"),
        parsing: .unconditional,
        help: "Colon-separated folders to search for build folders")
    var projects: String?

    /// The bash script's argument rules run first, so its exact errors, help
    /// text and exit codes survive; the parser then reads what they let through.
    static func main() async {
        // Numbers like "1.5GB" parse and print the same in every locale, in
        // this process and in every tool it runs.
        setenv("LC_ALL", "C", 1)
        setlocale(LC_ALL, "C")
        let terminal = StandardTerminal(command: Self.commandName)

        switch CommandLineOptions.check(Array(CommandLine.arguments.dropFirst()), command: Self.commandName) {
        case .help:
            terminal.write(CommandLineOptions.usage(Self.commandName))
            Darwin.exit(0)
        case let .failure(message):
            terminal.warn(message)
            Darwin.exit(1)
        case let .options(options):
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
            CommandLineOptions(run: self.run, yes: self.yes, skip: self.skip, projects: self.projects),
            environment: environment,
            dependencies: .live(environment: environment, passthroughOutput: true, command: Self.commandName),
            terminal: StandardTerminal(command: Self.commandName),
            command: Self.commandName)
        Darwin.exit(status)
    }

    /// devsweep, or devclean when run under the original script's name.
    static var commandName: CommandName {
        CommandName.invoked(as: CommandLine.arguments.first ?? "")
    }
}
