import ArgumentParser

@main
struct Gump: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gump",
        abstract: "Ephemeral Linux CI runners on macOS",
        subcommands: [InitCommand.self, RunOnceCommand.self, RunCommand.self]
    )
}
