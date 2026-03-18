import ArgumentParser
import Foundation

struct RunOnceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run-once",
        abstract: "Run a single ephemeral GitHub Actions runner in a Linux container"
    )

    @Option(help: "GitHub runner registration token")
    var token: String

    @Option(help: "Repository URL (e.g. https://github.com/owner/repo)")
    var url: String

    @Option(help: "Comma-separated runner labels")
    var labels: String?

    @Option(help: "Container image to use")
    var image: String?

    @Option(help: "CPU count for the container")
    var cpus: Int?

    @Option(help: "Memory in MB for the container")
    var memory: Int?

    mutating func run() async throws {
        try Preflight.check()

        let config = GumpConfig.load()

        let labels = labels ?? config.labels ?? "self-hosted,linux"
        let image = image ?? config.image ?? "ghcr.io/argylebits/gump-runner:latest"
        let cpus = cpus ?? config.cpus ?? 2
        let memory = memory ?? config.memory ?? 4096

        let runner = ContainerRunner(
            token: token,
            repoURL: url,
            labels: labels.split(separator: ",").map(String.init),
            image: image,
            cpus: cpus,
            memoryMB: memory
        )
        let exitCode = try await runner.run()
        if exitCode != 0 {
            throw ExitCode(exitCode)
        }
    }
}
