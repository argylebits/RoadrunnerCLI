import ArgumentParser

@main
struct Roadrunner: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "roadrunner",
        abstract: "Ephemeral Linux CI runners on macOS",
        version: "roadrunner \(appVersion)",
        subcommands: [InitCommand.self, RunOnceCommand.self, RunCommand.self, ServiceCommand.self]
    )
}
