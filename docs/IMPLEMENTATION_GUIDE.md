# GumpCI MVP Implementation Guide

This document contains everything a new agent needs to implement GumpCI from scratch. Read CLAUDE.md first for the project overview, then read this fully before writing any code.

## Goal

Build a CLI tool that:
1. Takes a GitHub runner registration token and repo URL as CLI arguments
2. Spins up an ephemeral Linux container (Ubuntu 24.04) via Apple's Containerization framework
3. Runs `actions/runner` inside it (downloaded at boot, configured with the provided token)
4. Waits for the runner to complete its one job (ephemeral mode)
5. Destroys the container
6. Exits with the runner's exit code

## Target UX

```bash
gumpci run-once \
  --token AABBCC... \
  --url https://github.com/owner/repo \
  --labels self-hosted,linux
```

---

## Prerequisites (must be satisfied BEFORE building)

### 1. Install the `container` CLI

Download from https://github.com/apple/container/releases (v0.10.0+). Double-click the `.pkg` installer. It installs to `/usr/local/bin/container`.

### 2. Start the container system

```bash
container system start
```

This installs:
- A Linux kernel (Kata Containers vmlinux, optimized for containers)
- The vminitd init filesystem (OCI image `ghcr.io/apple/containerization/vminit:latest`)
- Background services: container-apiserver, container-network-vmnet, container-core-images, container-runtime-linux

Data is stored at: `~/Library/Application Support/com.apple.container`

### 3. Verify the container system works

```bash
container run --rm ubuntu:24.04 echo "hello from container"
```

If this works, the kernel, initfs, networking, and image pulling are all functional. If this fails, debug this BEFORE attempting to build GumpCI.

### 4. Verify `container run` works with env vars and a longer script

```bash
container run --rm -e MY_VAR=hello ubuntu:24.04 /bin/bash -c 'echo $MY_VAR && apt-get update -qq && echo done'
```

This verifies env var injection and outbound networking (apt-get needs internet).

---

## Phase 0: Determine the API Approach

**This is the first thing to do when starting implementation. There are two viable approaches. Try Approach A first. If it doesn't work within ~1 hour, switch to Approach B.**

### Approach A: Programmatic (ContainerManager API)

Use the Containerization Swift package directly. This gives full programmatic control.

**Pros:** Clean, native Swift, proper exit code handling, no subprocess management.
**Cons:** Requires resolving kernel/initfs paths, signing, may hit undocumented API issues.

**How to validate (do this FIRST before writing the full CLI):**

1. Create a minimal test Swift package that imports `Containerization`
2. Try to build it — verify the package resolves and compiles
3. Ad-hoc sign the binary with the virtualization entitlement
4. Try to create a `ContainerManager` and run a trivial container (`echo hello`)
5. If this works, proceed with Approach A for the full implementation

**The critical unknowns for Approach A:**
- Where exactly does `ContainerManager` look for the kernel? (See "Kernel Resolution" section below)
- Does `initfsReference: "vminit:latest"` work with the `container` system's image store, or does it need its own?
- Does `network: nil` give outbound internet, or do we need to set up `VmnetNetwork`?

### Approach B: Subprocess Wrapper (container CLI)

Shell out to `/usr/local/bin/container run` as a subprocess. This is guaranteed to work if the `container` CLI works.

**Pros:** Guaranteed to work, no signing issues (container CLI is already signed), no API unknowns.
**Cons:** Less control over lifecycle, output parsing for exit codes, subprocess management.

```swift
import Foundation

func runContainer(token: String, repoURL: String, labels: [String], image: String) async throws -> Int32 {
    let bootScript = """
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl jq tar gzip sudo > /dev/null
    useradd -m -s /bin/bash runner
    echo 'runner ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
    ARCH=$(uname -m)
    case $ARCH in
        aarch64|arm64) RUNNER_ARCH="arm64" ;;
        x86_64)        RUNNER_ARCH="x64" ;;
    esac
    RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/^v//')
    mkdir -p /opt/runner && cd /opt/runner
    curl -sL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" | tar xz
    chown -R runner:runner /opt/runner
    sudo -u runner ./config.sh --url "$REPO_URL" --token "$RUNNER_TOKEN" --name "$RUNNER_NAME" --labels "$RUNNER_LABELS" --ephemeral --unattended --replace
    sudo -u runner ./run.sh
    """

    let process = Process()
    process.executableURL = URL(filePath: "/usr/local/bin/container")
    process.arguments = [
        "run", "--rm",
        "-e", "RUNNER_TOKEN=\(token)",
        "-e", "REPO_URL=\(repoURL)",
        "-e", "RUNNER_NAME=gumpci-\(UUID().uuidString.prefix(8))",
        "-e", "RUNNER_LABELS=\(labels.joined(separator: ","))",
        "-e", "DEBIAN_FRONTEND=noninteractive",
        "-c", "2",
        "-m", "4G",
        image,
        "/bin/bash", "-c", bootScript,
    ]

    // Forward stdout/stderr
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}
```

**This is the nuclear fallback.** It works, it's simple, and it's a perfectly valid MVP. The user doesn't care whether we use the Swift API or shell out — they care that the container runs their CI job.

---

## Kernel Resolution (for Approach A)

This is the biggest unknown. The `ContainerManager` requires a `Kernel` object:

```swift
let kernel = Kernel(path: URL(filePath: "/path/to/vmlinux"), platform: .linuxArm)
```

### Where to find the kernel

**Option 1: Use the `container` system's kernel**

The `container` system stores data at `~/Library/Application Support/com.apple.container`. After `container system start`, explore this directory to find where the kernel binary lives:

```bash
find ~/Library/Application\ Support/com.apple.container -name "vmlinux*" -o -name "kernel*" 2>/dev/null
```

The kernel may be stored as an OCI image blob (content-addressable), not a plain file. If so, you may need to use the ImageStore API to extract it, or find another way.

**Option 2: Download the Kata Containers kernel directly**

This is what the containerization Makefile does:

```bash
# Download Kata Containers 3.17.0 for arm64
KATA_URL="https://github.com/kata-containers/kata-containers/releases/download/3.17.0/kata-static-3.17.0-arm64.tar.xz"
mkdir -p /tmp/gumpci/kata
curl -sL "$KATA_URL" -o /tmp/gumpci/kata/kata.tar.xz
cd /tmp/gumpci/kata
tar -xf kata.tar.xz --strip-components=1
# Kernel is at: /tmp/gumpci/kata/opt/kata/share/kata-containers/vmlinux.container
```

Then use it:
```swift
let kernel = Kernel(
    path: URL(filePath: "/tmp/gumpci/kata/opt/kata/share/kata-containers/vmlinux.container"),
    platform: .linuxArm
)
```

**Option 3: Use `container system kernel set` to find the current kernel path**

```bash
# Check if there's a way to query the current kernel path
container system status  # may show kernel info
```

### How cctl resolves the kernel

In the `cctl` example tool (containerization repo), the kernel path is a **required CLI argument** (`--kernel`). There is NO automatic kernel discovery. The user passes it explicitly:

```bash
cctl run --kernel /path/to/vmlinux ubuntu:24.04 /bin/bash
```

This means for GumpCI's Approach A, we either:
1. Accept a `--kernel` flag (adds UX friction)
2. Auto-download the Kata kernel on first run (adds complexity but good UX)
3. Look in a well-known location (e.g., `~/.gumpci/kernel/vmlinux`)
4. Look in the `container` system's data directory (fragile, undocumented)

**Recommendation**: Auto-download the Kata kernel on first run to `~/.gumpci/kernel/vmlinux`, with an optional `--kernel` override flag.

### The initfs (vminitd) problem

`initfsReference: "vminit:latest"` refers to an OCI image in the local image store. For `cctl`, this image must be pre-loaded into the store. The `container` system loads it from `ghcr.io/apple/containerization/vminit:latest`.

For GumpCI, when using `ContainerManager` with `root: URL(filePath: "/tmp/gumpci/data")`, it creates its own separate ImageStore. The `vminit:latest` image won't be there unless we either:
1. Pull it ourselves: use the ImageStore API to pull `ghcr.io/apple/containerization/vminit:latest`
2. Share the `container` system's data directory as the root
3. Use the `initfs: Mount` init (non-async) instead of `initfsReference: String` (needs an actual rootfs file)

**Resolution steps at implementation time:**
1. Try `root: URL(filePath: expandedPath("~/Library/Application Support/com.apple.container"))` — share the container system's data dir
2. If that fails (permissions, conflicts), try pulling vminit ourselves: create our own ImageStore, pull `ghcr.io/apple/containerization/vminit:latest`
3. If that fails, use the `initfs: Mount` initializer with a pre-downloaded rootfs

---

## Phase 1: Project Scaffold

### Package.swift

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GumpCI",
    platforms: [
        .macOS(.v15)  // Match containerization package; use runtime #available checks for macOS 26
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/containerization", from: "0.26.0"),
        // If "from:" doesn't resolve, try: branch: "main"
        // If that doesn't resolve, try: .exact("0.26.5-prerelease")
    ],
    targets: [
        .executableTarget(
            name: "gumpci",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationOCI", package: "containerization"),
            ],
            path: "Sources/GumpCI",
            resources: [
                .copy("Resources/runner-boot.sh"),
            ]
        ),
    ]
)
```

**Version pinning notes:**
- Latest release: `0.26.5-prerelease` (Feb 28, 2026)
- Try `from: "0.26.0"` first (should pick up latest 0.26.x)
- If semver resolution fails (prereleases can be tricky), use `branch: "main"` or `.exact("0.26.5-prerelease")`
- If none work, pin to a specific commit

### Entitlements file: signing/vz.entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.virtualization</key>
    <true/>
</dict>
</plist>
```

### Build and sign workflow

```bash
# Build
swift build

# Sign (REQUIRED — without this, Virtualization.framework calls will fail)
codesign --force --sign - --timestamp=none --entitlements=signing/vz.entitlements .build/debug/gumpci

# Run
.build/debug/gumpci run-once --token ... --url ...
```

**`swift run` will NOT work** because SwiftPM doesn't apply entitlements. Always build + sign + run manually.

### Entry Point: GumpCI.swift

```swift
import ArgumentParser

@main
struct GumpCI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gumpci",
        abstract: "Ephemeral Linux CI runners on macOS",
        subcommands: [RunOnceCommand.self]
    )
}
```

### RunOnceCommand.swift

```swift
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
    var labels: String = "self-hosted,linux"

    @Option(help: "Container image to use")
    var image: String = "ubuntu:24.04"

    @Option(help: "CPU count for the container")
    var cpus: Int = 2

    @Option(help: "Memory in MB for the container")
    var memory: Int = 4096

    @Option(help: "Path to Linux kernel binary (auto-downloaded if not specified)")
    var kernel: String?

    mutating func run() async throws {
        let runner = ContainerRunner(
            token: token,
            repoURL: url,
            labels: labels.split(separator: ",").map(String.init),
            image: image,
            cpus: cpus,
            memoryMB: memory,
            kernelPath: kernel
        )
        let exitCode = try await runner.run()
        if exitCode != 0 {
            throw ExitCode(exitCode)
        }
    }
}
```

---

## Phase 2: Container Lifecycle (ContainerRunner.swift)

This is the core of the MVP. It wraps the Apple Containerization framework.

### How the Containerization Framework Works

The Containerization framework runs each Linux container in its own lightweight VM. The key types:

| Type | Purpose |
|------|---------|
| `ContainerManager` | Factory — creates containers from OCI images, manages kernel/initfs/networking |
| `LinuxContainer` | A single container — create, start, wait, stop |
| `LinuxContainer.Configuration` | CPU, memory, mounts, networking, process config |
| `LinuxProcessConfiguration` | Process arguments, env vars, working directory, user |
| `Kernel` | Linux kernel binary for the VM |
| `Mount` | Filesystem mount — block device, VirtioFS share, or generic |
| `NATInterface` | NAT networking for the container |
| `ExitStatus` | Exit code (Int32) + timestamp (Date) |
| `ImageStore` | Local OCI image storage/retrieval |

### Container Creation Flow

```
1. Resolve kernel binary (Kata Containers vmlinux)
2. Create ContainerManager (kernel + initfs ref + optional network + data root)
3. manager.create() — pulls OCI image if needed, creates LinuxContainer with config
4. container.create() — sets up VM, mounts rootfs
5. container.start() — boots VM, starts init process (vminitd), runs configured process
6. container.wait() — blocks until process exits, returns ExitStatus
7. container.stop() — cleanup VM resources
8. manager.delete() — remove container from manager
```

### Key Code Pattern (derived from cctl RunCommand.swift)

```swift
import Containerization
import ContainerizationOCI

// 1. Resolve kernel
let kernel = Kernel(
    path: URL(filePath: kernelPath),
    platform: .linuxArm
)

// 2. Set up ContainerManager
var manager = try await ContainerManager(
    kernel: kernel,
    initfsReference: "vminit:latest",  // OCI image ref in the local store
    root: dataDir                       // where to store images/containers
)

// 3. Create container from OCI image reference
let container = try await manager.create(
    containerID,
    reference: "docker.io/library/ubuntu:24.04",
    rootfsSizeInBytes: UInt64(10 * 1024 * 1024 * 1024)  // 10 GB
) { config in
    config.cpus = 2
    config.memoryInBytes = UInt64(4096) * 1024 * 1024  // 4 GB

    // Process configuration
    // NOTE: environmentVariables is [String] in KEY=VALUE format, NOT [String: String]
    config.process.arguments = ["/bin/bash", "/opt/gumpci/runner-boot.sh"]
    config.process.environmentVariables = [
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "RUNNER_TOKEN=\(token)",
        "REPO_URL=\(repoURL)",
        "RUNNER_LABELS=self-hosted,linux",
        "RUNNER_NAME=gumpci-abc123",
    ]
    config.process.workingDirectory = "/"

    // Mount the boot script into the container via VirtioFS
    config.mounts.append(
        .share(
            source: "/path/on/host/to/boot-script-dir",
            destination: "/opt/gumpci"
        )
    )
}

// 4. Lifecycle
try await container.create()
try await container.start()
let exitStatus = try await container.wait()
try await container.stop()

// 5. Cleanup
try await manager.delete(containerID)

// exitStatus.exitCode is Int32
```

### Complete ContainerRunner.swift Implementation Sketch

```swift
import Foundation
import Containerization
import ContainerizationOCI

struct ContainerRunner {
    let token: String
    let repoURL: String
    let labels: [String]
    let image: String
    let cpus: Int
    let memoryMB: Int
    let kernelPath: String?

    private let gumpciDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".gumpci")
    }()

    func run() async throws -> Int32 {
        let containerID = "gumpci-\(UUID().uuidString.prefix(8).lowercased())"

        // 1. Resolve kernel
        let resolvedKernelPath = try await resolveKernel()
        let kernel = Kernel(path: URL(filePath: resolvedKernelPath), platform: .linuxArm)

        // 2. Set up data directory
        let dataDir = gumpciDir.appending(path: "data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        print("[gumpci] Creating container \(containerID)...")

        // 3. Create ContainerManager
        var manager = try await ContainerManager(
            kernel: kernel,
            initfsReference: "vminit:latest",
            root: dataDir
        )

        // 4. Write boot script to temp location for mounting
        let bootScriptDir = gumpciDir.appending(path: "tmp/\(containerID)")
        try FileManager.default.createDirectory(at: bootScriptDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bootScriptDir) }

        let bootScriptDest = bootScriptDir.appending(path: "runner-boot.sh")
        guard let bundledScript = Bundle.module.url(forResource: "runner-boot", withExtension: "sh") else {
            throw GumpCIError.missingBootScript
        }
        try FileManager.default.copyItem(at: bundledScript, to: bootScriptDest)

        // 5. Create container
        let container = try await manager.create(
            containerID,
            reference: image,
            rootfsSizeInBytes: UInt64(10 * 1024 * 1024 * 1024)
        ) { config in
            config.cpus = cpus
            config.memoryInBytes = UInt64(memoryMB) * 1024 * 1024

            config.process.arguments = ["/bin/bash", "/opt/gumpci/runner-boot.sh"]
            config.process.environmentVariables = [
                "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                "RUNNER_TOKEN=\(token)",
                "REPO_URL=\(repoURL)",
                "RUNNER_NAME=\(containerID)",
                "RUNNER_LABELS=\(labels.joined(separator: ","))",
                "DEBIAN_FRONTEND=noninteractive",
                "HOME=/root",
            ]
            config.process.workingDirectory = "/"

            config.mounts.append(
                .share(source: bootScriptDir.path(), destination: "/opt/gumpci")
            )
        }

        // 6. Run
        print("[gumpci] Starting container...")
        try await container.create()
        try await container.start()

        print("[gumpci] Runner is active. Waiting for job completion...")
        let exitStatus = try await container.wait()

        print("[gumpci] Container exited with code \(exitStatus.exitCode)")

        // 7. Cleanup
        try await container.stop()
        try await manager.delete(containerID)

        return exitStatus.exitCode
    }

    /// Resolve the kernel binary path.
    /// Priority: explicit --kernel flag > cached download > fresh download
    private func resolveKernel() async throws -> String {
        // If user provided explicit path, use it
        if let kernelPath {
            guard FileManager.default.fileExists(atPath: kernelPath) else {
                throw GumpCIError.kernelNotFound(kernelPath)
            }
            return kernelPath
        }

        // Check cached kernel
        let cachedKernel = gumpciDir.appending(path: "kernel/vmlinux")
        if FileManager.default.fileExists(atPath: cachedKernel.path()) {
            return cachedKernel.path()
        }

        // Download Kata Containers kernel
        print("[gumpci] Downloading Linux kernel (Kata Containers 3.17.0)...")
        let kataURL = URL(string: "https://github.com/kata-containers/kata-containers/releases/download/3.17.0/kata-static-3.17.0-arm64.tar.xz")!

        let kernelDir = gumpciDir.appending(path: "kernel")
        try FileManager.default.createDirectory(at: kernelDir, withIntermediateDirectories: true)

        // Download and extract using tar
        let downloadPath = kernelDir.appending(path: "kata.tar.xz")
        let (downloadedURL, _) = try await URLSession.shared.download(from: kataURL)
        try FileManager.default.moveItem(at: downloadedURL, to: downloadPath)

        // Extract kernel binary
        let extractDir = kernelDir.appending(path: "extract")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.arguments = ["-xf", downloadPath.path(), "--strip-components=1", "-C", extractDir.path()]
        try tar.run()
        tar.waitUntilExit()

        let extractedKernel = extractDir.appending(path: "opt/kata/share/kata-containers/vmlinux.container")
        guard FileManager.default.fileExists(atPath: extractedKernel.path()) else {
            throw GumpCIError.kernelExtractionFailed
        }

        try FileManager.default.moveItem(at: extractedKernel, to: cachedKernel)

        // Clean up extraction artifacts
        try? FileManager.default.removeItem(at: downloadPath)
        try? FileManager.default.removeItem(at: extractDir)

        print("[gumpci] Kernel cached at \(cachedKernel.path())")
        return cachedKernel.path()
    }
}

enum GumpCIError: Error, CustomStringConvertible {
    case missingBootScript
    case kernelNotFound(String)
    case kernelExtractionFailed
    case containerFailed(Int32)

    var description: String {
        switch self {
        case .missingBootScript:
            return "Boot script not found in bundle"
        case .kernelNotFound(let path):
            return "Kernel not found at \(path)"
        case .kernelExtractionFailed:
            return "Failed to extract kernel from Kata Containers archive"
        case .containerFailed(let code):
            return "Container exited with code \(code)"
        }
    }
}
```

---

## Phase 3: Boot Script (runner-boot.sh)

This script runs inside the Ubuntu container at startup. Place at `Sources/GumpCI/Resources/runner-boot.sh`.

```bash
#!/bin/bash
set -euo pipefail

# These are passed as environment variables by ContainerRunner
: "${RUNNER_TOKEN:?RUNNER_TOKEN is required}"
: "${REPO_URL:?REPO_URL is required}"
: "${RUNNER_NAME:=gumpci-$(hostname)}"
: "${RUNNER_LABELS:=self-hosted,linux}"

echo "[gumpci] Starting runner boot sequence..."

# Install dependencies
echo "[gumpci] Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl jq tar gzip sudo > /dev/null

# Create runner user (actions/runner doesn't like running as root)
useradd -m -s /bin/bash runner
echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    aarch64|arm64) RUNNER_ARCH="arm64" ;;
    x86_64)        RUNNER_ARCH="x64" ;;
    *)             echo "[gumpci] Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Get latest runner version
echo "[gumpci] Fetching latest actions/runner version..."
RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/^v//')
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

# Download and extract
echo "[gumpci] Downloading actions/runner v${RUNNER_VERSION} (${RUNNER_ARCH})..."
mkdir -p /opt/runner
cd /opt/runner
curl -sL "$RUNNER_URL" | tar xz
chown -R runner:runner /opt/runner

# Configure runner (as runner user)
echo "[gumpci] Configuring runner..."
sudo -u runner ./config.sh \
    --url "$REPO_URL" \
    --token "$RUNNER_TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "$RUNNER_LABELS" \
    --ephemeral \
    --unattended \
    --replace

# Start runner (as runner user)
echo "[gumpci] Starting runner..."
sudo -u runner ./run.sh
EXIT_CODE=$?

echo "[gumpci] Runner exited with code $EXIT_CODE"
exit $EXIT_CODE
```

**Key decisions:**
- Creates a `runner` user — `actions/runner` complains when run as root
- Auto-detects architecture (arm64 for Apple Silicon, x64 for Rosetta)
- Downloads latest runner version — no hardcoded version to maintain
- Uses `--ephemeral` — runner handles one job then exits
- Uses `--replace` — in case a stale registration exists with the same name

---

## Gap Analysis: What We Don't Know Yet

These are things that can ONLY be resolved by actually running code. They are ordered by severity.

### GAP 1: Does `ContainerManager` work with our own data root? (HIGH)

**The question**: When we create `ContainerManager(kernel:, initfsReference: "vminit:latest", root: ~/.gumpci/data)`, does it know how to pull the `vminit:latest` image from `ghcr.io/apple/containerization/vminit:latest`? Or does `initfsReference` only look in the local store?

**How to resolve**: Try it. If it fails with "image not found", we need to either:
1. Share the `container` system's data directory as root: `root: ~/Library/Application Support/com.apple.container`
2. Pre-pull the image into our store using `ImageStore` API
3. Use the non-async `init(kernel:initfs:root:)` initializer that takes a `Mount` instead of a reference string — but then we need the actual initfs rootfs file

**The cctl source code shows**: `initfsReference: "vminit:latest"` — this expects the image to already be in the local ImageStore. In the cctl workflow, the user must have run `cctl rootfs create` to load the vminit image first.

**Most likely resolution**: Use the `container` system's data directory (share its image store).

### GAP 2: Does `network: nil` provide outbound internet? (HIGH)

**The question**: If we don't pass a `Network` object, does the container get any networking at all?

**How to resolve**: Create a container with `network: nil` and try `curl google.com` inside it.

**If no**: We need to create a `VmnetNetwork` or use the `container` system's networking. `VmnetNetwork` is macOS 26+ and may require the container system's network XPC service.

**Fallback**: If networking is problematic, Approach B (subprocess) bypasses this entirely since the `container` CLI handles networking.

### GAP 3: Does `Mount.share()` work for VirtioFS file sharing? (MEDIUM)

**The question**: Can we mount a host directory into the container using `config.mounts.append(.share(source:destination:))`?

**How to resolve**: Try it and verify the file appears inside the container.

**If no**: Alternative — inline the boot script as a long `/bin/bash -c '...'` argument. This is uglier but avoids mounts entirely. Or write the script to the rootfs after image extraction using `container.copyIn()`.

### GAP 4: Does `swift build` resolve the containerization package? (MEDIUM)

**The question**: Can SwiftPM resolve `from: "0.26.0"` for a package that only has prerelease tags?

**How to resolve**: Create the Package.swift and run `swift build`. If it fails:
1. Try `branch: "main"`
2. Try `.exact("0.26.5-prerelease")`
3. Try `.revision("specific-commit-hash")`

### GAP 5: Does ad-hoc signing with the virtualization entitlement work? (MEDIUM)

**The question**: Does `codesign --force --sign - --entitlements=signing/vz.entitlements` allow the binary to use Virtualization.framework?

**How to resolve**: Build, sign, and try to create a `VZVirtualMachine` (or just let ContainerManager try). This is exactly what Apple's containerization Makefile does, so it should work.

**If no**: We may need a real Developer ID certificate. This would be a significant blocker for casual development.

### GAP 6: What exact image reference format does `manager.create()` expect? (LOW)

**The question**: Is it `"ubuntu:24.04"` or `"docker.io/library/ubuntu:24.04"` or `"library/ubuntu:24.04"`?

**How to resolve**: Try each. The `cctl` source uses short references in its CLI, which likely map to docker.io/library/ internally.

---

## Step-by-Step Implementation Checklist

When you come back to implement, follow this exact order:

### Step 1: Verify prerequisites
- [ ] `container` CLI is installed (`which container`)
- [ ] `container system start` has been run
- [ ] `container run --rm ubuntu:24.04 echo hello` works
- [ ] `container run --rm -e TEST=yes ubuntu:24.04 /bin/bash -c 'echo $TEST'` works

### Step 2: Create project scaffold
- [ ] Create `Package.swift` (try `from: "0.26.0"` first)
- [ ] Create `Sources/GumpCI/GumpCI.swift` (entry point)
- [ ] Create `signing/vz.entitlements`
- [ ] Run `swift build` — verify it compiles (this may take a while on first resolve)

### Step 3: Validate Approach A with minimal test
- [ ] In `GumpCI.swift`, try creating a `Kernel` and `ContainerManager`
- [ ] Sign the binary: `codesign --force --sign - --timestamp=none --entitlements=signing/vz.entitlements .build/debug/gumpci`
- [ ] Run the binary — see what happens
- [ ] If ContainerManager creation works, try running a trivial container (echo hello)
- [ ] **If this doesn't work within ~1 hour, switch to Approach B (subprocess)**

### Step 4: Implement the full ContainerRunner
- [ ] If Approach A works: implement `ContainerRunner.swift` with kernel resolution, container lifecycle
- [ ] If Approach B: implement the subprocess wrapper
- [ ] Create `Sources/GumpCI/Resources/runner-boot.sh`
- [ ] Create `RunOnceCommand.swift`
- [ ] Build, sign, test with a trivial command first (not a full runner, just echo)

### Step 5: End-to-end test with GitHub Actions
- [ ] Create a test workflow in a repo (see Testing Strategy below)
- [ ] Get a registration token from GitHub Settings > Actions > Runners > New self-hosted runner
- [ ] Run gumpci with the token
- [ ] Verify the job completes in the GitHub Actions UI
- [ ] Verify the container is cleaned up after

---

## Testing Strategy

### Test Workflow (create in a test repo)

```yaml
name: Test Self-Hosted
on: workflow_dispatch
jobs:
  test:
    runs-on: [self-hosted, linux]
    steps:
      - run: echo "Hello from GumpCI!"
      - run: uname -a
      - run: cat /etc/os-release
      - run: df -h
      - run: free -h
```

### Getting a Registration Token

1. Go to your test repo on GitHub
2. Settings > Actions > Runners
3. Click "New self-hosted runner"
4. The token is shown on the setup page (starts with `A...`)
5. The token expires in 1 hour — get a fresh one each time

### Running the Test

```bash
# Build and sign
swift build && codesign --force --sign - --timestamp=none --entitlements=signing/vz.entitlements .build/debug/gumpci

# Run (token is from GitHub, url is your test repo)
.build/debug/gumpci run-once \
  --token AXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX \
  --url https://github.com/your-user/your-test-repo \
  --labels self-hosted,linux
```

### What Success Looks Like

1. Container starts (sub-second)
2. Boot script runs, installs deps, downloads actions/runner (~30-60s)
3. Runner registers with GitHub and picks up the queued job
4. Job executes (you see it go green in GitHub Actions UI)
5. Runner exits, container is destroyed
6. `gumpci` exits with code 0

### What Failure Looks Like and How to Debug

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `swift build` fails on containerization dependency | Version resolution | Try `branch: "main"` or `.exact(...)` |
| Signing error or entitlement failure | Missing codesign step | Run the codesign command |
| "Kernel not found" | Kata download failed | Check URL, try manual download |
| "vminit:latest not found" | Image not in local store | Try sharing container system's data dir |
| Container starts but no network | Network not configured | Pass `network:` parameter or try Approach B |
| Runner can't register with GitHub | Token expired or wrong URL | Get fresh token, verify URL |
| Runner registers but no job picked up | Labels mismatch | Ensure workflow `runs-on` matches `--labels` |
| Container hangs | Runner waiting for job | Trigger the workflow via `workflow_dispatch` |

---

## Post-MVP Roadmap

Once the MVP works:

1. **Daemon mode**: Add `gumpci run` that polls GitHub for jobs using GitHub App auth
2. **Image caching**: Pre-pull Ubuntu image, cache `actions/runner` binary in a custom image
3. **Custom images**: Allow user to specify a pre-built image with runner pre-installed
4. **Concurrency**: Run multiple containers for parallel jobs
5. **macOS VM support**: Virtualization.framework for `[self-hosted, macos]` jobs
6. **Config file**: YAML configuration for daemon mode
7. **Observability**: Structured logging with swift-log
