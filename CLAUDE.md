# GumpCI

Ephemeral Linux CI runners on macOS via Apple's Containerization framework.

## What This Is

A Swift CLI tool that spins up an ephemeral Linux container (Ubuntu) on macOS 26 using Apple's Containerization framework, runs a single GitHub Actions job inside it via `actions/runner --ephemeral`, and destroys the container when done.

**MVP scope**: One command (`gumpci run-once`), one container, one job, done.

## Quick Reference

```bash
# Prerequisites (one-time)
# 1. Install container CLI from https://github.com/apple/container/releases (v0.10.0+)
# 2. Run: container system start
# 3. Verify: container run ubuntu:24.04 echo hello

# Build (must ad-hoc sign with virtualization entitlement — see Development Notes)
swift build
codesign --force --sign - --timestamp=none --entitlements=signing/vz.entitlements .build/debug/gumpci

# Run
.build/debug/gumpci run-once \
  --token AABBCC... \
  --url https://github.com/owner/repo \
  --labels self-hosted,linux

# Test
swift test
```

## Project Structure

```
GumpCI/
├── Package.swift                         # Swift 6.2, macOS 15 platform (runtime checks for macOS 26)
├── signing/
│   └── vz.entitlements                   # com.apple.security.virtualization entitlement
├── Sources/GumpCI/
│   ├── GumpCI.swift                      # @main entry point, top-level AsyncParsableCommand
│   ├── RunOnceCommand.swift              # `run-once` subcommand — token, url, labels args
│   └── ContainerRunner.swift             # Wraps Containerization framework — create/run/wait/destroy
├── Resources/
│   └── runner-boot.sh                    # Injected into container — downloads+configures+runs actions/runner
└── docs/
    ├── IMPLEMENTATION_GUIDE.md           # Detailed implementation plan with code patterns and gap analysis
    └── CONTAINERIZATION_API_REFERENCE.md # Apple Containerization framework API reference
```

## Architecture Decisions

- **Apple Containerization framework** (not Docker, not raw Virtualization.framework) — each container runs in its own lightweight VM, sub-second startup, OCI-compatible
- **`swift-argument-parser`** only explicit dependency beyond Containerization — MVP is minimal
- **No GitHub App auth** — user manually provides a registration token from GitHub Settings
- **No polling/scheduler** — single-shot `run-once` command
- **Boot script approach** — container runs Ubuntu, boot script downloads `actions/runner` at startup (~30-60s cost, acceptable for CI job durations, avoids custom image maintenance)

## Key Constraints

- **macOS 26+ required** — Containerization framework is macOS 26 only
- **Apple Silicon required** — Containerization uses Virtualization.framework
- **`container` CLI must be installed and running** — `container system start` must be running to provide kernel, initfs (vminitd), networking, and image management services
- **Outbound networking required** — container needs internet to download `actions/runner` and for CI jobs
- **Entitlement required** — binary must be ad-hoc signed with `com.apple.security.virtualization` entitlement (plain `swift run` will NOT work — see Development Notes)

## Containerization Framework Key Facts

- Swift package at `https://github.com/apple/containerization` (latest: `0.26.5-prerelease`)
- Package.swift declares platform `.macOS(.v15)` but container features require macOS 26 at runtime
- Each container = lightweight Linux VM (not namespace isolation)
- Uses `ContainerManager` to create containers from OCI image references
- Requires a Linux kernel + initfs (vminitd) — provided by `container system start`
- `LinuxContainer` type: `.create()` → `.start()` → `.wait()` → `.stop()`
- Process config: `LinuxProcessConfiguration(arguments:environmentVariables:workingDirectory:)`
- **Env vars are `[String]` in `KEY=VALUE` format, NOT `[String: String]`**
- File injection via `Mount.share(source:destination:)` (VirtioFS)
- Networking handled by the `container` system's vmnet services
- Exit status: `ExitStatus { exitCode: Int32, exitedAt: Date }`

## Data Locations

| What | Path |
|------|------|
| Container system data (images, kernels) | `~/Library/Application Support/com.apple.container` |
| Containerization package data (cctl) | `~/Library/Application Support/com.apple.containerization` |
| Kernel binary (Kata Containers) | Downloaded by `container system start`, stored in system data dir |
| vminitd initfs | OCI image `ghcr.io/apple/containerization/vminit:latest`, pulled by system |

## Development Notes

### Entitlement & Code Signing (CRITICAL)

The Containerization framework uses Virtualization.framework under the hood. On Apple Silicon, **all binaries must be signed**, and Virtualization.framework requires the `com.apple.security.virtualization` entitlement. This means:

1. **`swift run` will NOT work** — SwiftPM doesn't apply entitlements during `swift run`
2. You must `swift build` then ad-hoc sign the binary:
   ```bash
   swift build
   codesign --force --sign - --timestamp=none --entitlements=signing/vz.entitlements .build/debug/gumpci
   .build/debug/gumpci run-once --token ... --url ...
   ```
3. Create `signing/vz.entitlements`:
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

This is exactly what Apple does in the containerization repo's own Makefile.

### Swift Concurrency

- Swift 6.2 strict concurrency — all mutable state in actors
- The Containerization package pulls in significant transitive deps (grpc-swift, swift-nio, swift-protobuf, async-http-client, swift-crypto, etc.) — this is expected
- Environment: macOS 26.3.1, Swift 6.2.3, Apple Silicon

## Handoff Materials

The `ci-runner-handoff/` directory contains the original full-scope orchestrator design. The MVP deliberately ignores most of it. Relevant pieces:
- `shared/guest-boot.sh` — reference boot script (for macOS VMs, but the pattern applies)
- `agent/github-api-spec.json` — GitHub API details (post-MVP)
- `agent/schemas.json` — data model definitions (post-MVP)
