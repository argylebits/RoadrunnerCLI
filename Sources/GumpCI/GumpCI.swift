import ArgumentParser

@main
struct GumpCI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gumpci",
        abstract: "Ephemeral Linux CI runners on macOS",
        subcommands: [RunOnceCommand.self]
    )
}
