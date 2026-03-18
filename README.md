# Roadrunner

Ephemeral Linux CI runners on macOS. Beep beep!

Roadrunner spins up throwaway Linux containers on your Mac (via Apple's [Containerization framework](https://github.com/apple/containerization)), runs a GitHub Actions job inside each one, and destroys it when done. No persistent runners, no stale state, no Docker required.

## How It Works

```
GitHub Actions triggers a job
        |
        v
  Roadrunner daemon picks it up
        |
        v
  Fresh Linux container boots (~seconds)
        |
        v
  Job runs (tests, builds, deploys, etc.)
        |
        v
  Container is destroyed
        |
        v
  New container stands ready for the next job
```

Each job gets a clean environment. Nothing leaks between runs.

## Quick Start

```bash
# Install the container CLI (requires macOS 26+ on Apple Silicon)
brew install container
brew services start container

# Install Roadrunner
brew tap argylebits/tap
brew install roadrunner-cli

# Configure (walks you through GitHub App setup)
roadrunner init

# Run
roadrunner run
```

## Requirements

- macOS 26+ on Apple Silicon
- [`container` CLI](https://github.com/apple/container/releases) (v0.10.0+)
- A [GitHub App](#github-app-setup) for automatic token management

## Commands

### `roadrunner run` (daemon mode)

Runs continuously, auto-provisioning ephemeral runners for each job. Reads credentials from `~/.roadrunner/config.yaml`.

```bash
roadrunner run
```

Ctrl-C to stop gracefully.

### `roadrunner run-once` (single-shot)

Runs one container for one job using a manual registration token.

```bash
roadrunner run-once --token <TOKEN> --url https://github.com/owner/repo
```

## GitHub App Setup

1. Create a GitHub App at https://github.com/settings/apps/new
2. Permissions: **Self-hosted runners: Read & write**
3. Uncheck Webhook
4. Install on your org/repo
5. Generate a private key
6. Note the **App ID** and **Installation ID**

See [docs/SETUP.md](docs/SETUP.md) for detailed instructions.

## Configuration

Run `roadrunner init` to create `~/.roadrunner/config.yaml` interactively. Or edit it manually:

```yaml
app-id: 12345
installation-id: 67890
private-key: ~/.roadrunner/private-key.pem
url: https://github.com/your-org
image: ghcr.io/argylebits/roadrunner:latest
labels: self-hosted,linux
cpus: 2
memory: 4096
```

CLI flags override config values. See [docs/config.example.yaml](docs/config.example.yaml).

## Using in Your Workflows

Set `runs-on: [self-hosted, linux]` and you're done. The runner image has Swift pre-installed, and any other language works too:

```yaml
jobs:
  test:
    runs-on: [self-hosted, linux]
    steps:
      - uses: actions/checkout@v4
      - run: swift test
```

See [docs/workflow-templates/](docs/workflow-templates/) for more examples.

## Running as a Service

```bash
# Install and start the launchd service (auto-starts on login)
roadrunner service install

# Check status
roadrunner service status

# Restart
roadrunner service restart

# Remove
roadrunner service uninstall
```

## Documentation

- [Setup Guide](docs/SETUP.md) — full installation and configuration walkthrough
- [Workflow Templates](docs/workflow-templates/) — ready-to-use GitHub Actions workflows
- [Example Config](docs/config.example.yaml) — annotated config file

## License

Apache 2.0 — see [LICENSE](LICENSE).
