import ArgumentParser
import Foundation

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create ~/.gump/config.yaml interactively or via flags"
    )

    @Option(help: "GitHub App ID")
    var appId: Int?

    @Option(help: "GitHub App installation ID")
    var installationId: Int?

    @Option(help: "Path to GitHub App private key PEM file")
    var privateKey: String?

    @Option(help: "GitHub repository or organization URL")
    var url: String?

    @Option(help: "Container image to use")
    var image: String?

    @Option(help: "Comma-separated runner labels")
    var labels: String?

    @Option(help: "CPU count for each container")
    var cpus: Int?

    @Option(help: "Memory in MB for each container")
    var memory: Int?

    @Flag(help: "Overwrite existing config without prompting")
    var force: Bool = false

    mutating func run() throws {
        let configDir = GumpConfig.configDir.path()
        let configPath = GumpConfig.configPath.path()

        // Check for existing config
        if FileManager.default.fileExists(atPath: configPath) && !force {
            if allFlagsProvided {
                throw InitError.configExists
            }
            print("Config already exists at \(configPath)")
            guard promptYesNo("Overwrite?", default: false) else {
                print("Aborted.")
                throw ExitCode.failure
            }
        }

        // Gather values: use flags, fall back to interactive prompts
        let appId = try self.appId ?? promptInt("GitHub App ID")
        let installationId = try self.installationId ?? promptInt("Installation ID")
        let privateKey = try resolvePrivateKey(self.privateKey)
        let url = try resolveURL(self.url)
        let image = self.image ?? promptOptional("Container image", default: "ghcr.io/argylebits/gump-runner:latest")
        let labels = self.labels ?? promptOptional("Runner labels", default: "self-hosted,linux")
        let cpus = self.cpus ?? promptOptionalInt("CPUs per container", default: 2)
        let memory = self.memory ?? promptOptionalInt("Memory (MB) per container", default: 4096)

        // Create config directory
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        // Write config
        var yaml = """
        # Gump configuration
        # See: https://github.com/ArgyleBits/Gump

        app-id: \(appId)
        installation-id: \(installationId)
        private-key: \(privateKey)
        url: \(url)
        image: \(image)
        labels: \(labels)
        cpus: \(cpus)
        memory: \(memory)
        """
        yaml.append("\n")

        try yaml.write(toFile: configPath, atomically: true, encoding: .utf8)

        print("")
        print("Config written to \(configPath)")
        print("Next: run `gump run` to start the daemon.")
    }

    // MARK: - Prompts

    private func promptString(_ label: String) throws -> String {
        print("\(label): ", terminator: "")
        guard let line = readLine(), !line.isEmpty else {
            throw InitError.missingInput(label)
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    private func promptInt(_ label: String) throws -> Int {
        let value = try promptString(label)
        guard let n = Int(value) else {
            throw InitError.invalidInput(label, value)
        }
        return n
    }

    private func promptOptional(_ label: String, default defaultValue: String) -> String {
        print("\(label) [\(defaultValue)]: ", terminator: "")
        guard let line = readLine(), !line.trimmingCharacters(in: .whitespaces).isEmpty else {
            return defaultValue
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    private func promptOptionalInt(_ label: String, default defaultValue: Int) -> Int {
        print("\(label) [\(defaultValue)]: ", terminator: "")
        guard let line = readLine(),
              !line.trimmingCharacters(in: .whitespaces).isEmpty,
              let n = Int(line.trimmingCharacters(in: .whitespaces)) else {
            return defaultValue
        }
        return n
    }

    private func promptYesNo(_ label: String, default defaultValue: Bool) -> Bool {
        let hint = defaultValue ? "Y/n" : "y/N"
        print("\(label) [\(hint)]: ", terminator: "")
        guard let line = readLine(), !line.trimmingCharacters(in: .whitespaces).isEmpty else {
            return defaultValue
        }
        return line.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("y")
    }

    // MARK: - Validation

    private func resolvePrivateKey(_ flagValue: String?) throws -> String {
        let raw: String
        if let flagValue {
            raw = flagValue
        } else {
            raw = try promptString("Private key path (e.g. ~/.gump/private-key.pem)")
        }

        let expanded = (raw as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expanded) else {
            throw InitError.fileNotFound(raw)
        }

        return raw
    }

    private func resolveURL(_ flagValue: String?) throws -> String {
        let raw: String
        if let flagValue {
            raw = flagValue
        } else {
            raw = try promptString("GitHub URL (org or repo, e.g. https://github.com/your-org)")
        }

        // Validate it parses
        _ = try RunnerTarget.parse(url: raw)

        return raw
    }

    private var allFlagsProvided: Bool {
        appId != nil && installationId != nil && privateKey != nil && url != nil
    }
}

enum InitError: Error, CustomStringConvertible {
    case configExists
    case missingInput(String)
    case invalidInput(String, String)
    case fileNotFound(String)

    var description: String {
        switch self {
        case .configExists:
            "Config already exists at ~/.gump/config.yaml (use --force to overwrite)"
        case .missingInput(let field):
            "No value provided for: \(field)"
        case .invalidInput(let field, let value):
            "Invalid value for \(field): \(value)"
        case .fileNotFound(let path):
            "File not found: \(path)"
        }
    }
}
