import Foundation

struct ContainerRunner {
    let token: String
    let repoURL: String
    let labels: [String]
    let image: String
    let cpus: Int
    let memoryMB: Int
    func run() async throws -> Int32 {
        let containerID = "gump-\(UUID().uuidString.prefix(8).lowercased())"

        // Write boot script to temp location
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: containerID)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        guard let bundledScript = Bundle.module.url(forResource: "runner-boot", withExtension: "sh") else {
            throw GumpError.missingBootScript
        }
        let bootScript = try String(contentsOf: bundledScript, encoding: .utf8)

        print("[gump] Starting container \(containerID)...")

        let process = Process()
        process.executableURL = URL(filePath: "/usr/local/bin/container")
        process.arguments = [
            "run", "--rm",
            "-e", "RUNNER_TOKEN=\(token)",
            "-e", "REPO_URL=\(repoURL)",
            "-e", "RUNNER_NAME=\(containerID)",
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
        process.waitUntilExit()

        let exitCode = process.terminationStatus
        print("[gump] Container \(containerID) exited with code \(exitCode)")
        return exitCode
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
