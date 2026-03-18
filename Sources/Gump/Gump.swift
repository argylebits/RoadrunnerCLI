import ArgumentParser

@main
struct Gump: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gump",
        abstract: "Ephemeral Linux CI runners on macOS",
        subcommands: [RunOnceCommand.self, RunCommand.self]
    )
}
