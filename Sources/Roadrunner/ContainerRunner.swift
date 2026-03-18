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

    // Embedded boot script — avoids Bundle.module which requires a .bundle
    // directory next to the binary at runtime (breaks Homebrew installs).
    // Source of truth until a better embedding solution is in place.
    static let bootScript = """
        #!/bin/bash
        set -euo pipefail

        : "${RUNNER_TOKEN:?RUNNER_TOKEN is required}"
        : "${REPO_URL:?REPO_URL is required}"
        : "${RUNNER_NAME:=roadrunner-$(hostname)}"
        : "${RUNNER_LABELS:=self-hosted,linux}"

        echo "[roadrunner] Starting runner boot sequence..."

        # Check if runner is pre-installed (custom image) or needs downloading
        if [ -d /home/runner/actions-runner ]; then
            echo "[roadrunner] Using pre-installed actions/runner"
            RUNNER_DIR=/home/runner/actions-runner
        else
            echo "[roadrunner] Installing dependencies..."
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq curl jq tar gzip sudo libicu-dev > /dev/null

            id runner &>/dev/null || {
                useradd -m -s /bin/bash runner
                echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
            }

            ARCH=$(uname -m)
            case $ARCH in
                aarch64|arm64) RUNNER_ARCH="arm64" ;;
                x86_64)        RUNNER_ARCH="x64" ;;
                *)             echo "[roadrunner] Unsupported architecture: $ARCH"; exit 1 ;;
            esac

            echo "[roadrunner] Fetching latest actions/runner version..."
            RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/^v//')
            RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

            echo "[roadrunner] Downloading actions/runner v${RUNNER_VERSION} (${RUNNER_ARCH})..."
            mkdir -p /home/runner/actions-runner
            cd /home/runner/actions-runner
            curl -sL "$RUNNER_URL" | tar xz
            chown -R runner:runner /home/runner/actions-runner
            RUNNER_DIR=/home/runner/actions-runner
        fi

        cd "$RUNNER_DIR"

        echo "[roadrunner] Configuring runner..."
        sudo -u runner ./config.sh \
            --url "$REPO_URL" \
            --token "$RUNNER_TOKEN" \
            --name "$RUNNER_NAME" \
            --labels "$RUNNER_LABELS" \
            --ephemeral \
            --unattended \
            --replace

        echo "[roadrunner] Starting runner..."
        sudo -u runner ./run.sh
        EXIT_CODE=$?

        echo "[roadrunner] Runner exited with code $EXIT_CODE"
        exit $EXIT_CODE
        """

    let token: String
    let repoURL: String
    let labels: [String]
    let image: String
    let cpus: Int
    let memoryMB: Int

    func run(onStart: ((_ containerName: String, _ process: Process) -> Void)? = nil) async throws -> Int32 {
        let containerName = "roadrunner-\(UUID().uuidString.prefix(8).lowercased())"

        print("[roadrunner] Starting container \(containerName)...")

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
            "/bin/bash", "-c", Self.bootScript,
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

        print("[roadrunner] Container \(containerName) exited with code \(exitCode)")
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

enum RoadrunnerError: Error, CustomStringConvertible {
    case containerFailed(Int32)
    case invalidPrivateKey(String)
    case jwtSigningFailed(String)
    case gitHubAPIError(String)
    case invalidURL(String)
    case missingConfig(String)

    var description: String {
        switch self {
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
            "Missing required config: --\(field) (set via CLI flag or ~/.roadrunner/config.yaml)"
        }
    }
}
