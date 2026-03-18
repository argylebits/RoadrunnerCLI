import Foundation

struct ContainerRunner {
    /// Resolve the container CLI path, checking common install locations
    static let containerCLI: String = {
        let candidates = [
            "/usr/local/bin/container",
            "/opt/homebrew/bin/container",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "container"  // fall back to PATH lookup
    }()

    let token: String
    let repoURL: String
    let labels: [String]
    let image: String
    let cpus: Int
    let memoryMB: Int

    func run(onStart: ((_ containerName: String, _ process: Process) -> Void)? = nil) async throws -> Int32 {
        let containerName = "gump-\(UUID().uuidString.prefix(8).lowercased())"

        guard let bundledScript = Bundle.module.url(forResource: "runner-boot", withExtension: "sh") else {
            throw GumpError.missingBootScript
        }
        let bootScript = try String(contentsOf: bundledScript, encoding: .utf8)

        print("[gump] Starting container \(containerName)...")

        let process = Process()
        process.executableURL = URL(filePath: Self.containerCLI)
        process.arguments = [
            "run", "--rm",
            "--name", containerName,
            "-e", "RUNNER_TOKEN=\(token)",
            "-e", "REPO_URL=\(repoURL)",
            "-e", "RUNNER_NAME=\(containerName)",
            "-e", "RUNNER_LABELS=\(labels.joined(separator: ","))",
            "-e", "DEBIAN_FRONTEND=noninteractive",
            "-c", "\(cpus)",
            "-m", "\(memoryMB)M",
            image,
            "/bin/bash", "-c", bootScript,
        ]

        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        onStart?(containerName, process)

        let exitCode = await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
        }

        print("[gump] Container \(containerName) exited with code \(exitCode)")
        return exitCode
    }

    /// Stop a container via the container CLI
    static func stopContainer(name: String) {
        let stop = Process()
        stop.executableURL = URL(filePath: Self.containerCLI)
        stop.arguments = ["stop", name]
        stop.standardOutput = FileHandle.nullDevice
        stop.standardError = FileHandle.nullDevice
        try? stop.run()
        stop.waitUntilExit()
    }
}

enum GumpError: Error, CustomStringConvertible {
    case missingBootScript
    case containerFailed(Int32)
    case invalidPrivateKey(String)
    case jwtSigningFailed(String)
    case gitHubAPIError(String)
    case invalidURL(String)
    case missingConfig(String)

    var description: String {
        switch self {
        case .missingBootScript:
            "Boot script not found in bundle"
        case .containerFailed(let code):
            "Container exited with code \(code)"
        case .invalidPrivateKey(let reason):
            "Invalid private key: \(reason)"
        case .jwtSigningFailed(let reason):
            "JWT signing failed: \(reason)"
        case .gitHubAPIError(let reason):
            "GitHub API error: \(reason)"
        case .invalidURL(let url):
            "Invalid GitHub URL: \(url). Expected https://github.com/owner/repo or https://github.com/org"
        case .missingConfig(let field):
            "Missing required config: --\(field) (set via CLI flag or ~/.gump/config.yaml)"
        }
    }
}
