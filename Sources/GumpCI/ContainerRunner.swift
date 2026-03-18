import Foundation

struct ContainerRunner {
    let token: String
    let repoURL: String
    let labels: [String]
    let image: String
    let cpus: Int
    let memoryMB: Int
    func run() async throws -> Int32 {
        let containerID = "gumpci-\(UUID().uuidString.prefix(8).lowercased())"

        // Write boot script to temp location
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: containerID)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        guard let bundledScript = Bundle.module.url(forResource: "runner-boot", withExtension: "sh") else {
            throw GumpCIError.missingBootScript
        }
        let bootScript = try String(contentsOf: bundledScript, encoding: .utf8)

        print("[gumpci] Starting container \(containerID)...")

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
        print("[gumpci] Container \(containerID) exited with code \(exitCode)")
        return exitCode
    }
}

enum GumpCIError: Error, CustomStringConvertible {
    case missingBootScript
    case containerFailed(Int32)

    var description: String {
        switch self {
        case .missingBootScript:
            "Boot script not found in bundle"
        case .containerFailed(let code):
            "Container exited with code \(code)"
        }
    }
}
