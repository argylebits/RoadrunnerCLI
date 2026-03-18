import ArgumentParser
import Foundation

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create ~/.roadrunner/config.yaml interactively or via flags"
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

    @Option(help: "Shell alias name for roadrunner (default: rr)")
    var alias: String?

    @Flag(help: "Skip adding a shell alias")
    var noAlias: Bool = false

    mutating func run() throws {
        let configDir = RoadrunnerConfig.configDir.path()
        let configPath = RoadrunnerConfig.configPath.path()

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
        let image = self.image ?? promptOptional("Container image", default: "ghcr.io/argylebits/roadrunner:latest")
        let labels = self.labels ?? promptOptional("Runner labels", default: "self-hosted,linux")
        let cpus = self.cpus ?? promptOptionalInt("CPUs per container", default: 2)
        let memory = self.memory ?? promptOptionalInt("Memory (MB) per container", default: 4096)

        // Create config directory
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        // Write config
        var yaml = """
        # Roadrunner configuration
        # See: https://github.com/argylebits/RoadrunnerCLI

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
        print("Next: run `roadrunner run` to start the daemon.")

        // Shell alias
        if !noAlias {
            let aliasName: String
            if let explicit = self.alias {
                aliasName = explicit
            } else if allFlagsProvided {
                // Non-interactive mode without --alias: skip
                return
            } else {
                aliasName = promptOptional("Add shell alias?", default: "rr")
            }

            if !aliasName.isEmpty {
                addShellAlias(name: aliasName)
            }
        }
    }

    // MARK: - Shell Alias

    private func addShellAlias(name: String) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let rcFile = ShellAlias.rcFilePath(forShell: shell) else {
            print("Unknown shell (\(shell)), skipping alias.")
            return
        }

        let expanded = (rcFile as NSString).expandingTildeInPath
        let result = ShellAlias.add(name: name, toFile: expanded)

        switch result {
        case .added:
            print("Added `alias \(name)='roadrunner'` to \(rcFile)")
            print("Run `source \(rcFile)` or open a new terminal to use it.")
        case .alreadyExists:
            print("Alias already exists in \(rcFile)")
        case .failed(let error):
            print("Could not write to \(rcFile): \(error)")
            print("Add manually: alias \(name)='roadrunner'")
        }
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
            raw = try promptString("Private key path (e.g. ~/.roadrunner/private-key.pem)")
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
            "Config already exists at ~/.roadrunner/config.yaml (use --force to overwrite)"
        case .missingInput(let field):
            "No value provided for: \(field)"
        case .invalidInput(let field, let value):
            "Invalid value for \(field): \(value)"
        case .fileNotFound(let path):
            "File not found: \(path)"
        }
    }
}

enum ShellAliasResult: Equatable {
    case added
    case alreadyExists
    case failed(String)
}

enum ShellAlias {
    /// Returns the rc file path (unexpanded) for a given shell, or nil if unknown.
    static func rcFilePath(forShell shell: String) -> String? {
        if shell.hasSuffix("zsh") {
            return "~/.zshrc"
        } else if shell.hasSuffix("bash") {
            return "~/.bashrc"
        }
        return nil
    }

    /// Build the alias line for a given name.
    static func aliasLine(name: String) -> String {
        "alias \(name)='roadrunner'"
    }

    /// Add an alias to the given rc file. Creates the file if it doesn't exist.
    static func add(name: String, toFile path: String) -> ShellAliasResult {
        let line = aliasLine(name: name)

        // Check if alias already exists
        if let contents = try? String(contentsOfFile: path, encoding: .utf8),
           contents.contains(line) {
            return .alreadyExists
        }

        do {
            let url = URL(filePath: path)

            if !FileManager.default.fileExists(atPath: path) {
                // Create the file with the alias
                try "\(line)\n".write(to: url, atomically: true, encoding: .utf8)
            } else {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                handle.write(Data("\n\(line)\n".utf8))
                handle.closeFile()
            }
            return .added
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
