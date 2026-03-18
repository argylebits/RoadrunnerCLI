# Apple Containerization Framework — API Reference for GumpCI

Quick reference for the Apple Containerization Swift package as it pertains to building GumpCI. This is distilled from the source code at https://github.com/apple/containerization.

## Package Info

- **Repo**: https://github.com/apple/containerization
- **Swift tools version**: 6.2
- **Minimum platform**: macOS 15 (but container features require macOS 26 at runtime)
- **License**: Apache 2.0

### Products (libraries we care about)

| Product | Purpose |
|---------|---------|
| `Containerization` | Core — LinuxContainer, ContainerManager, Kernel, Mount, etc. |
| `ContainerizationOCI` | OCI image handling — ImageStore, registries |
| `ContainerizationEXT4` | EXT4 filesystem creation (used internally for rootfs) |

### Transitive Dependencies

The package pulls in: grpc-swift, swift-protobuf, swift-nio, async-http-client, swift-crypto, swift-system, swift-collections, swift-nio-ssl, zstd (1.5.7 exact).

---

## Core Types

### ContainerManager

Factory for creating containers. Manages kernel, initfs, image store, and networking.

```swift
import Containerization

// Init with explicit ImageStore
public init(
    kernel: Kernel,
    initfs: Mount,
    imageStore: ImageStore,
    network: Network? = nil,
    rosetta: Bool = false,
    nestedVirtualization: Bool = false
) throws

// Init with root directory (creates ImageStore internally)
public init(
    kernel: Kernel,
    initfs: Mount,
    root: URL? = nil,
    network: Network? = nil,
    rosetta: Bool = false,
    nestedVirtualization: Bool = false
) throws

// Init with initfs as OCI image reference (async — pulls if needed)
public init(
    kernel: Kernel,
    initfsReference: String,      // e.g. "vminit:latest"
    imageStore: ImageStore,
    network: Network? = nil,
    rosetta: Bool = false,
    nestedVirtualization: Bool = false
) async throws

// Init with initfs reference + root directory
public init(
    kernel: Kernel,
    initfsReference: String,
    root: URL? = nil,
    network: Network? = nil,
    rosetta: Bool = false,
    nestedVirtualization: Bool = false
) async throws
```

**Creating a container from an OCI image reference:**
```swift
let container = try await manager.create(
    "container-id",                          // unique ID
    reference: "docker.io/library/ubuntu:24.04",  // OCI image ref
    rootfsSizeInBytes: 10 * 1024 * 1024 * 1024,  // rootfs size
    readOnly: false                               // writable rootfs
) { config in
    // Configure via LinuxContainer.Configuration
    config.cpus = 2
    config.memoryInBytes = 4096 * 1024 * 1024
    config.process.arguments = ["/bin/bash", "/script.sh"]
    config.process.environmentVariables = ["PATH=/usr/bin", "FOO=bar"]
}
```

**Other methods:**
```swift
mutating func releaseNetwork(_ id: String) throws
mutating func delete(_ id: String) throws
```

---

### Kernel

Represents the Linux kernel binary for the container VM.

```swift
public struct Kernel: Sendable, Codable {
    public let path: URL                    // path to vmlinux binary
    public let platform: SystemPlatform     // .linuxArm or .linuxAmd
    public let commandLine: CommandLine     // kernel boot args

    public init(
        path: URL,
        platform: SystemPlatform,
        commandLine: CommandLine = .init()
    )
}

// SystemPlatform
public enum SystemPlatform {
    case linuxArm
    case linuxAmd
}
```

**Where to get a kernel:**
- The `container` CLI installs one via `container system start`
- Kata Containers project publishes optimized kernels
- The containerization repo has a `kernel/` directory with build instructions
- Kernel binary is typically at a path like `/opt/kata/share/kata-containers/vmlinux.container`

---

### LinuxContainer

The main container type. Created by `ContainerManager`.

```swift
public final class LinuxContainer: Container, Sendable {
    public let id: String
    public let rootfs: Mount
    public let writableLayer: Mount?
    public let config: Configuration
}
```

**Lifecycle methods:**
```swift
try await container.create()    // Initialize VM, mount rootfs
try await container.start()     // Boot VM, start process
let status = try await container.wait()  // Wait for process exit
try await container.stop()      // Cleanup
```

**Additional methods:**
```swift
try await container.kill()                    // Force terminate
try await container.exec(process)             // Run additional process
try await container.resize(to: Terminal.Size) // Resize PTY
try await container.copyIn(...)               // Copy files into container
try await container.copyOut(...)              // Copy files out
let stats = try await container.statistics()  // Runtime metrics
```

---

### LinuxContainer.Configuration

```swift
public struct Configuration: Sendable {
    public var process: LinuxProcessConfiguration = .init()
    public var cpus: Int = 4
    public var memoryInBytes: UInt64 = 1024.mib()    // 1 GB default
    public var hostname: String?
    public var sysctl: [String: String] = [:]
    public var interfaces: [any Interface] = []
    public var sockets: [UnixSocketConfiguration] = []
    public var mounts: [Mount] = LinuxContainer.defaultMounts()
    public var dns: DNS?
    public var hosts: Hosts?
    public var virtualization: Bool = false
    public var bootLog: BootLog?
    public var ociRuntimePath: String?
    public var useInit: Bool = false
}
```

---

### LinuxProcessConfiguration

```swift
public struct LinuxProcessConfiguration: Sendable {
    public var arguments: [String] = []
    public var environmentVariables: [String] = [
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    ]
    public var workingDirectory: String = "/"
    public var user: ContainerizationOCI.User = .init()
    public var noNewPrivileges: Bool = false
    public var capabilities: LinuxCapabilities = .allCapabilities
    public var rlimits: [LinuxRLimit] = []
    public var terminal: Bool = false
    public var stdin: ReaderStream?
    public var stdout: Writer?
    public var stderr: Writer?

    public init()
    public init(
        arguments: [String],
        environmentVariables: [String] = [...],
        workingDirectory: String = "/",
        user: ContainerizationOCI.User = .init(),
        rlimits: [LinuxRLimit] = [],
        noNewPrivileges: Bool = false,
        capabilities: LinuxCapabilities = .allCapabilities,
        terminal: Bool = false,
        stdin: ReaderStream? = nil,
        stdout: Writer? = nil,
        stderr: Writer? = nil
    )
    public init(from config: ImageConfig)  // from OCI image config
}
```

**Note**: `environmentVariables` is `[String]` in `KEY=VALUE` format, NOT `[String: String]`.

---

### Mount

```swift
public struct Mount: Sendable {
    public var type: String
    public var source: String
    public var destination: String
    public var options: [String]
    public var runtimeOptions: RuntimeOptions

    public enum RuntimeOptions: Sendable {
        case virtioblk([String])    // Virtio block device
        case virtiofs([String])     // VirtioFS share (host dir → guest dir)
        case any([String])          // Generic mount
    }

    // Convenience factories:

    // Block device mount (for disk images)
    public static func block(
        format: String,
        source: String,
        destination: String,
        options: [String] = [],
        runtimeOptions: [String] = []
    ) -> Self

    // VirtioFS share (host directory shared into container)
    public static func share(
        source: String,        // host path
        destination: String,   // guest path
        options: [String] = [],
        runtimeOptions: [String] = []
    ) -> Self

    // Generic mount
    public static func any(
        type: String,
        source: String,
        destination: String,
        options: [String] = [],
        runtimeOptions: [String] = []
    ) -> Self
}
```

**For GumpCI**: Use `.share()` to mount the boot script directory into the container:
```swift
config.mounts.append(
    .share(source: "/host/path/to/scripts", destination: "/opt/gumpci")
)
```

---

### ExitStatus

```swift
public struct ExitStatus: Sendable {
    public var exitCode: Int32
    public var exitedAt: Date

    public init(exitCode: Int32)                    // exitedAt = .now
    public init(exitCode: Int32, exitedAt: Date)
}
```

---

### NATInterface

```swift
public struct NATInterface: Interface {
    public var ipv4Address: CIDRv4
    public var ipv4Gateway: IPv4Address?
    public var macAddress: MACAddress?
    public var mtu: UInt32

    public init(
        ipv4Address: CIDRv4,
        ipv4Gateway: IPv4Address?,
        macAddress: MACAddress? = nil,
        mtu: UInt32 = 1500
    )
}
```

---

### ImageStore

Manages local OCI image storage. Created internally by `ContainerManager` or explicitly.

```swift
// Key method for image retrieval:
func get(reference: String, pull: Bool = true) async throws -> Image
// If pull=true and image not found locally, pulls from registry
```

---

## Practical Patterns

### Minimal Container Run

```swift
import Containerization

// Resolve kernel (from container system or bundled)
let kernel = Kernel(
    path: URL(filePath: "/path/to/vmlinux"),
    platform: .linuxArm
)

// Create manager
var manager = try await ContainerManager(
    kernel: kernel,
    initfsReference: "vminit:latest",
    root: URL(filePath: "/tmp/gumpci/data")
)

// Create container
let container = try await manager.create(
    "my-container",
    reference: "ubuntu:24.04",
    rootfsSizeInBytes: 10_737_418_240  // 10 GB
) { config in
    config.cpus = 2
    config.memoryInBytes = 4_294_967_296  // 4 GB
    config.process.arguments = ["/bin/echo", "hello world"]
}

// Run
try await container.create()
try await container.start()
let exit = try await container.wait()
try await container.stop()
try await manager.delete("my-container")

print("Exit code: \(exit.exitCode)")
```

### With Environment Variables

```swift
config.process.environmentVariables = [
    "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    "MY_SECRET=secret_value",
    "MY_CONFIG=some_config",
]
```

### With VirtioFS Mount

```swift
config.mounts.append(
    .share(source: "/Users/me/shared", destination: "/mnt/host")
)
```

---

## Companion CLI: `container`

The `container` CLI (https://github.com/apple/container) is a Docker-like tool built on the Containerization package. Useful for:
- **Testing**: `container run ubuntu:24.04 echo hello` to verify the framework works
- **Kernel management**: `container system start` installs the default kernel/initfs
- **Debugging**: `container logs <id>` to see container output

### Key Commands

```bash
container system start              # Start services, install kernel
container system stop               # Stop services
container run [opts] IMAGE [CMD]    # Run a container
container run -e KEY=VAL IMAGE CMD  # With env vars
container run -v /host:/guest IMAGE # With volume mount
container run --rm IMAGE CMD        # Auto-remove on exit
container run -d IMAGE CMD          # Detached (background)
container run -c 2 -m 4G IMAGE CMD # With resource limits
container image pull IMAGE          # Pull an image
container image ls                  # List local images
container ls                        # List containers
container stop ID                   # Stop a container
container rm ID                     # Remove a container
container system kernel set PATH    # Use custom kernel
```

---

---

## How cctl (the reference CLI) Works End-to-End

The `cctl` tool in the containerization repo is the canonical example of using the Containerization package programmatically. Here's exactly how it works:

### Data Directory

```swift
// cctl.swift — the app stores all data here:
static let appRoot: URL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("com.apple.containerization")
// Resolves to: ~/Library/Application Support/com.apple.containerization/
```

Two stores are created at this root:
- `ContentStore` at `appRoot/content` — content-addressable blob storage
- `ImageStore` using the ContentStore — OCI image management

### Kernel Resolution

**cctl does NOT auto-discover kernels.** The kernel path is a required `--kernel` CLI flag:

```swift
@Option(name: [.customLong("kernel"), .customShort("k")])
public var kernel: String  // User must pass the path
```

Instantiated as:
```swift
let kernel = Kernel(path: URL(fileURLWithPath: kernel), platform: .linuxArm)
```

### InitFS Resolution

The initfs is hardcoded as an OCI image reference:
```swift
initfsReference: "vminit:latest"
```

This must already exist in the local ImageStore. The containerization Makefile builds it with:
```bash
./bin/cctl rootfs create --vminitd vminitd/bin/vminitd --vmexec vminitd/bin/vmexec --image vminit:latest bin/init.rootfs.tar.gz
```

### The `container` CLI's Data Directory

The higher-level `container` CLI (https://github.com/apple/container) stores everything at:
```
~/Library/Application Support/com.apple.container
```

This includes kernel, vminit images, pulled container images, and container state. The `--app-root` flag can change this location.

### Kernel Source

Both tools use the Kata Containers project kernel:
```
URL: https://github.com/kata-containers/kata-containers/releases/download/3.17.0/kata-static-3.17.0-arm64.tar.xz
After extraction: opt/kata/share/kata-containers/vmlinux.container
```

### Code Signing

Both `cctl` and the `container` CLI require ad-hoc signing with the virtualization entitlement:
```bash
codesign --force --sign - --timestamp=none --entitlements=signing/vz.entitlements bin/cctl
```

Entitlements file (`signing/vz.entitlements`):
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

---

## Architecture: What Happens When You Run a Container

Understanding the full stack helps debug issues:

```
Your Swift code
  → ContainerManager.create()
    → ImageStore.get(reference:pull:true)  // pulls OCI image from registry
    → EXT4Unpacker                         // unpacks image layers into ext4 block device
    → LinuxContainer()                     // creates container object
  → container.create()
    → Configures VZVirtualMachineConfiguration (via Virtualization.framework)
    → Attaches: kernel, initfs, rootfs block device, network, VirtioFS shares
  → container.start()
    → VZVirtualMachine.start()             // boots the Linux kernel
    → Kernel loads vminitd as init process (PID 1)
    → vminitd mounts rootfs, configures networking, opens gRPC on vsock port 1024
    → vminitd spawns your configured process (/bin/bash, etc.)
  → container.wait()
    → Waits for process exit via gRPC over vsock
    → Returns ExitStatus
  → container.stop()
    → Terminates VM, cleans up resources
```

Each container is a full Linux VM, not a namespace. This means:
- Sub-second startup (optimized kernel + minimal init)
- Full hardware isolation between containers
- Each container has its own kernel, network stack, filesystem
- Higher memory overhead than Docker (~128MB+ per container)
- The `vminitd` init process provides the host-guest communication channel

---

## References

- **Containerization repo**: https://github.com/apple/containerization
- **Container CLI repo**: https://github.com/apple/container
- **WWDC25 session**: https://developer.apple.com/videos/play/wwdc2025/346/
- **API docs**: https://apple.github.io/containerization/documentation/
- **Deep dive blog**: https://anil.recoil.org/notes/apple-containerisation
- **Kernel build instructions**: https://github.com/apple/containerization/tree/main/kernel
- **DeepWiki summary**: https://deepwiki.com/apple/containerization
- **Container data storage**: https://github.com/apple/container/discussions/718
- **Container how-to guide**: https://github.com/apple/container/blob/main/docs/how-to.md
- **Kata Containers kernel releases**: https://github.com/kata-containers/kata-containers/releases
