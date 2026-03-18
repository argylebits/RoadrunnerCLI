import ArgumentParser
import Foundation

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run as a daemon, automatically provisioning ephemeral runners for GitHub Actions jobs"
    )

    @Option(help: "GitHub App ID")
    var appId: Int?

    @Option(help: "GitHub App installation ID")
    var installationId: Int?

    @Option(help: "Path to GitHub App private key PEM file")
    var privateKey: String?

    @Option(help: "GitHub repository or organization URL")
    var url: String?

    @Option(help: "Comma-separated runner labels")
    var labels: String?

    @Option(help: "Container image to use")
    var image: String?

    @Option(help: "CPU count for each container")
    var cpus: Int?

    @Option(help: "Memory in MB for each container")
    var memory: Int?

    mutating func run() async throws {
        let config = GumpConfig.load()

        // Merge CLI flags over config file values
        guard let appId = appId ?? config.appId else {
            throw GumpError.missingConfig("app-id")
        }
        guard let installationId = installationId ?? config.installationId else {
            throw GumpError.missingConfig("installation-id")
        }
        guard let privateKey = privateKey ?? config.privateKey else {
            throw GumpError.missingConfig("private-key")
        }
        guard let url = url ?? config.url else {
            throw GumpError.missingConfig("url")
        }

        let labels = labels ?? config.labels ?? "self-hosted,linux"
        let image = image ?? config.image ?? "gump-runner:latest"
        let cpus = cpus ?? config.cpus ?? 2
        let memory = memory ?? config.memory ?? 4096

        let target = try RunnerTarget.parse(url: url)

        let jwtGenerator = try JWTGenerator(pemPath: privateKey, appID: String(appId))
        let tokenManager = TokenManager(jwtGenerator: jwtGenerator, installationID: String(installationId))
        let client = GitHubAppClient(tokenManager: tokenManager, target: target)

        let targetDesc: String
        switch target {
        case .repo(let owner, let name): targetDesc = "\(owner)/\(name)"
        case .org(let name): targetDesc = "\(name) (org)"
        }

        print("[gump] Starting daemon mode...")
        print("[gump] GitHub App ID: \(appId), Installation ID: \(installationId)")
        print("[gump] Target: \(targetDesc)")
        print("[gump] Image: \(image)")

        // Graceful shutdown on SIGINT/SIGTERM
        let shouldStop = ManagedAtomic(false)

        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            if shouldStop.value {
                print("\n[gump] Force quitting...")
                _exit(1)
            }
            print("\n[gump] Received SIGINT, will exit after current container finishes...")
            shouldStop.value = true
        }
        signal(SIGINT, SIG_IGN)
        sigintSource.resume()

        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource.setEventHandler {
            print("\n[gump] Received SIGTERM, will exit after current container finishes...")
            shouldStop.value = true
        }
        signal(SIGTERM, SIG_IGN)
        sigtermSource.resume()

        while !shouldStop.value {
            do {
                print("[gump] Requesting runner registration token...")
                let registrationToken = try await client.getRegistrationToken()

                let runner = ContainerRunner(
                    token: registrationToken,
                    repoURL: url,
                    labels: labels.split(separator: ",").map(String.init),
                    image: image,
                    cpus: cpus,
                    memoryMB: memory
                )

                let exitCode = try await runner.run()
                if exitCode != 0 {
                    print("[gump] Runner exited with code \(exitCode)")
                }
            } catch {
                print("[gump] Error: \(error)")
                print("[gump] Retrying in 10 seconds...")
                try? await Task.sleep(for: .seconds(10))
            }

            if !shouldStop.value {
                print("[gump] Starting next runner in 2 seconds...")
                try? await Task.sleep(for: .seconds(2))
            }
        }

        print("[gump] Daemon stopped.")

        // Keep sources alive
        withExtendedLifetime((sigintSource, sigtermSource)) {}
    }
}

/// Simple thread-safe wrapper for a Bool flag.
final class ManagedAtomic: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool

    init(_ value: Bool) {
        _value = value
    }

    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
