# Roadrunner

<!-- Fresco image -->
![RoadrunnerCLI](https://pub-d60dc12417c74d04b3dd6a1ed43e02c4.r2.dev/roadrunner-cli/2026-03-25-182427.jpg)

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

Run `roadrunner init` to set up `~/.roadrunner/`. The wizard asks for your GitHub App details and the path to your private key PEM file, then copies it into place:

```bash
roadrunner init
# or non-interactively:
roadrunner init --app-id 12345 --installation-id 67890 \
  --private-key ~/Downloads/my-app.private-key.pem \
  --url https://github.com/your-org
```

This creates:
- `~/.roadrunner/config.yaml` — app ID, installation ID, URL, image, labels, etc.
- `~/.roadrunner/private-key.pem` — your GitHub App private key (chmod 600)

The private key is always stored at `~/.roadrunner/private-key.pem`. The `--private-key` flag on `init` is the *source* path — the file you downloaded from GitHub. Your original file is not modified.

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
