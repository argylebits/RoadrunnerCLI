# Roadrunner Setup Guide

## Prerequisites

- macOS 26+ on Apple Silicon
- `container` CLI installed from https://github.com/apple/container/releases (v0.10.0+)
- A GitHub App with **Self-hosted runners: Read & write** permission

## One-Time Setup

### 1. Install the container CLI

**Option A: Homebrew (recommended)**

```bash
brew install container
brew services start container
```

This installs the CLI and starts the container system as a background service (auto-starts on login).

**Option B: Manual install**

Download `container-*-installer-signed.pkg` from https://github.com/apple/container/releases. Double-click to install. Then start the container system:

```bash
container system start
```

Say **Y** when prompted to install the default kernel.

**Verify it works:**

```bash
container run --rm ubuntu:24.04 echo "hello"
```

### 3. Build Roadrunner

```bash
cd /path/to/Roadrunner
swift build -c release
```

Copy the binary somewhere permanent:

```bash
sudo mkdir -p /usr/local/bin
sudo cp .build/release/roadrunner /usr/local/bin/roadrunner
```

### 4. Build the custom runner image

```bash
cd images
container build -t ghcr.io/argylebits/roadrunner:latest -f Containerfile -m 4G .
```

This takes a few minutes (downloads Swift ~950MB). The image is cached locally after the first build.

### 5. Create a GitHub App

1. Go to https://github.com/settings/apps/new
2. Name: "Roadrunner" (or whatever you like)
3. Homepage URL: anything
4. **Uncheck** "Active" under Webhook
5. Permissions: **Self-hosted runners → Read & write**
6. Click "Create GitHub App"
7. Note the **App ID** (numeric, shown at the top of the app settings page)
8. Under "Private keys", click **Generate a private key** — downloads a `.pem` file
9. Install the app on your org/repo:
   - Go to https://github.com/settings/apps/your-app-name/installations
   - Click "Install" on your target org or repo
   - Note the **Installation ID** from the URL: `https://github.com/settings/installations/<INSTALLATION_ID>`

### 6. Configure Roadrunner

Run the setup wizard:

```bash
roadrunner init
```

This will prompt you for:
- **GitHub App ID** and **Installation ID** (from step 5)
- **Path to your private key PEM file** (e.g. `~/Downloads/your-app-name.private-key.pem`)
- Container image, labels, CPU, and memory settings

The wizard creates `~/.roadrunner/` and:
- Copies your private key to `~/.roadrunner/private-key.pem` (chmod 600) — your original file is not modified
- Writes `~/.roadrunner/config.yaml` with your settings

Or run non-interactively:

```bash
roadrunner init \
  --app-id 12345 \
  --installation-id 67890 \
  --private-key ~/Downloads/your-app-name.private-key.pem \
  --url https://github.com/your-org
```

An example config is at `docs/config.example.yaml`.

## Running Manually

With a config file in place:

```bash
roadrunner run
```

Or with explicit flags (these override config values):

```bash
roadrunner run \
  --app-id <APP_ID> \
  --installation-id <INSTALLATION_ID> \
  --private-key ~/.roadrunner/private-key.pem \
  --url https://github.com/<org-or-owner/repo> \
  --image ghcr.io/argylebits/roadrunner:latest
```

The daemon will loop: register a runner, wait for a job, run it, clean up, repeat. Ctrl-C to stop gracefully (stops the container and exits). Ctrl-C again to force quit.

### One-off run (manual token)

For quick testing without a GitHub App:

1. Go to your repo → Settings → Actions → Runners → New self-hosted runner
2. Copy the registration token
3. Run:

```bash
roadrunner run-once \
  --token <TOKEN> \
  --url https://github.com/<org-or-owner/repo> \
  --image ghcr.io/argylebits/roadrunner:latest
```

## Running as a Background Service (launchd)

### 1. Make sure the container system starts on login

```bash
container system start
```

The container CLI registers itself with launchd automatically when you run `container system start`. It will start on login going forward.

### 2. Install the service

```bash
roadrunner service install
```

This creates a launchd plist at `~/Library/LaunchAgents/com.argylebits.roadrunner.plist`, loads it, and starts the daemon. It will restart automatically on login.

### 3. Managing the service

```bash
# Check status
roadrunner service status

# View logs
tail -f /tmp/roadrunner.log

# Restart
roadrunner service restart

# Reinstall (e.g. after upgrading roadrunner)
roadrunner service install --force

# Remove
roadrunner service uninstall
```

## Workflow Configuration

Roadrunner runs any GitHub Actions workflow — it's language-agnostic. Just set `runs-on: [self-hosted, linux]`.

The `ghcr.io/argylebits/roadrunner:latest` image has Swift pre-installed:

```yaml
jobs:
  test:
    runs-on: [self-hosted, linux]
    steps:
      - uses: actions/checkout@v4
      - run: swift test
```

For other languages, the same image works — Python is included in Ubuntu, and you can install anything else in a workflow step:

```yaml
jobs:
  test:
    runs-on: [self-hosted, linux]
    steps:
      - uses: actions/checkout@v4
      - run: pip install -r requirements.txt
      - run: pytest
```

See `docs/workflow-templates/` for ready-to-use examples.

## Updating

### Update Roadrunner

```bash
brew upgrade roadrunner

# Reinstall the service to pick up the new binary
roadrunner service install --force
```

### Update the runner image (new Swift version, etc.)

```bash
cd /path/to/Roadrunner/images
container build --no-cache -t ghcr.io/argylebits/roadrunner:latest -f Containerfile -m 4G .
# Restart roadrunner — the next container will use the new image
```

#### Keeping the image up to date

The `ghcr.io/argylebits/roadrunner:latest` image pins to `swiftly install latest` and the latest `actions/runner` at build time. Options for staying current:

- **Manual rebuild** — run `container build --no-cache ...` when you want a new Swift version. Simplest approach; Swift releases are infrequent.
- **Scheduled rebuild** — create a cron job or launchd timer that rebuilds the image weekly/monthly.
- **Version pinning** — edit the Containerfile to pin specific Swift and runner versions, update intentionally.

The image only needs rebuilding when Swift releases a new version or `actions/runner` has a breaking change.

### Update the container system

Download the latest `container` CLI from https://github.com/apple/container/releases and reinstall.
