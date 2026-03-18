# Gump

Ephemeral Linux CI runners on macOS via Apple's Containerization framework.

## What This Is

A Swift CLI tool that spins up ephemeral Linux containers on macOS 26 using Apple's `container` CLI, runs GitHub Actions jobs inside them via `actions/runner --ephemeral`, and destroys the container when done.

Two modes:
- `gump run-once` — single-shot: one container, one job, done
- `gump run` — daemon mode: auto-generates tokens via GitHub App, loops containers for each job

## Quick Reference

```bash
# Build
swift build

# Run (daemon mode, reads ~/.gump/config.yaml)
.build/debug/gump run

# Run (single-shot with manual token)
.build/debug/gump run-once --token AABBCC... --url https://github.com/owner/repo

# Test
swift test
```

## Project Structure

```
Gump/
├── Package.swift
├── Sources/Gump/
│   ├── Gump.swift                       # @main entry point
│   ├── RunCommand.swift                 # `run` daemon subcommand
│   ├── RunOnceCommand.swift             # `run-once` single-shot subcommand
│   ├── ContainerRunner.swift            # Shells out to `container run`, error types
│   ├── Config.swift                     # Loads ~/.gump/config.yaml
│   ├── Preflight.swift                  # Checks container CLI and system status
│   ├── GitHubAuth/
│   │   ├── JWTGenerator.swift           # RS256 JWT via Security.framework
│   │   ├── TokenManager.swift           # Installation token caching/refresh
│   │   └── GitHubAppClient.swift        # GitHub API: registration tokens, URL parsing
│   └── Resources/
│       └── runner-boot.sh               # Injected into container at boot
├── Tests/GumpTests/
│   ├── ConfigTests.swift
│   ├── URLParserTests.swift
│   ├── JWTTests.swift
│   └── TokenManagerTests.swift
├── images/
│   └── Containerfile                    # Custom image: Ubuntu + Swift + actions/runner
├── signing/
│   └── vz.entitlements                  # com.apple.security.virtualization
└── docs/
    ├── SETUP.md                         # Full setup guide including launchd
    ├── config.example.yaml              # Example ~/.gump/config.yaml
    ├── workflow-templates/              # Drop-in GitHub Actions workflows
    ├── IMPLEMENTATION_GUIDE.md          # Original implementation plan (historical)
    └── CONTAINERIZATION_API_REFERENCE.md # Containerization API reference (historical)
```

## Architecture

- **Approach B (subprocess)** — shells out to `/usr/local/bin/container run` rather than using the Containerization Swift package programmatically. The programmatic API had unresolved initfs issues; the CLI just works.
- **`swift-argument-parser`** is the only dependency
- **GitHub App auth** for daemon mode — JWT signing via Security.framework (RS256), no additional dependencies
- **Config file** at `~/.gump/config.yaml` — CLI flags override config values
- **Custom container image** (`ghcr.io/argylebits/gump-runner:latest`) — Ubuntu 24.04 + Swift + actions/runner pre-installed for fast startup
- **Boot script** detects pre-installed runner (custom image) or falls back to downloading everything (bare Ubuntu)

## Key Constraints

- **macOS 26+ required** — `container` CLI requires macOS 26
- **Apple Silicon required**
- **`container` CLI must be installed** — from https://github.com/apple/container/releases
- **`container system start` must be running** — provides kernel, networking, image management
- **Outbound networking required** — for GitHub API and CI jobs

## Configuration

All config lives at `~/.gump/`:

| File | Purpose |
|------|---------|
| `config.yaml` | App ID, installation ID, private key path, URL, image, labels, cpus, memory |
| `private-key.pem` | GitHub App private key |

See `docs/config.example.yaml` for the format.

## Development

```bash
# Build and run
swift build
.build/debug/gump run

# Run tests
swift test

# Build custom runner image
cd images
container build -t ghcr.io/argylebits/gump-runner:latest -f Containerfile -m 4G .
```

No code signing needed — Approach B uses the already-signed `container` CLI.
