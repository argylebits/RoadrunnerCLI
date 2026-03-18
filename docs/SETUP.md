# Gump Setup Guide

## Prerequisites

- macOS 26+ on Apple Silicon
- `container` CLI installed from https://github.com/apple/container/releases (v0.10.0+)
- A GitHub App with **Self-hosted runners: Read & write** permission

## One-Time Setup

### 1. Install the container CLI

Download `container-*-installer-signed.pkg` from the releases page. Double-click to install. It installs to `/usr/local/bin/container`.

### 2. Start the container system

```bash
container system start
```

This downloads a Linux kernel and starts background services. Say **Y** when prompted to install the default kernel.

Verify it works:

```bash
container run --rm ubuntu:24.04 echo "hello"
```

### 3. Build Gump

```bash
cd /path/to/Gump
swift build -c release
```

Copy the binary somewhere permanent:

```bash
sudo mkdir -p /usr/local/bin
sudo cp .build/release/gump /usr/local/bin/gump
```

### 4. Build the custom runner image

```bash
cd images
container build -t gump-runner:latest -f Containerfile -m 4G .
```

This takes a few minutes (downloads Swift ~950MB). The image is cached locally after the first build.

### 5. Create a GitHub App

1. Go to https://github.com/settings/apps/new
2. Name: "Gump Runner" (or whatever you like)
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

### 6. Configure Gump

Create the config directory and move your private key:

```bash
mkdir -p ~/.gump
mv ~/Downloads/your-app-name.*.private-key.pem ~/.gump/private-key.pem
chmod 600 ~/.gump/private-key.pem
```

Create `~/.gump/config.yaml` with your values:

```yaml
app-id: 12345
installation-id: 67890
private-key: ~/.gump/private-key.pem
url: https://github.com/your-org
image: gump-runner:latest
labels: self-hosted,linux
cpus: 2
memory: 4096
```

An example config is at `docs/config.example.yaml`.

## Running Manually

With a config file in place:

```bash
gump run
```

Or with explicit flags (these override config values):

```bash
gump run \
  --app-id <APP_ID> \
  --installation-id <INSTALLATION_ID> \
  --private-key ~/.gump/private-key.pem \
  --url https://github.com/<org-or-owner/repo> \
  --image gump-runner:latest
```

The daemon will loop: register a runner, wait for a job, run it, clean up, repeat. Ctrl-C to stop gracefully (stops the container and exits). Ctrl-C again to force quit.

### One-off run (manual token)

For quick testing without a GitHub App:

1. Go to your repo → Settings → Actions → Runners → New self-hosted runner
2. Copy the registration token
3. Run:

```bash
gump run-once \
  --token <TOKEN> \
  --url https://github.com/<org-or-owner/repo> \
  --image gump-runner:latest
```

## Running as a Background Service (launchd)

### 1. Make sure the container system starts on login

```bash
container system start
```

The container CLI registers itself with launchd automatically when you run `container system start`. It will start on login going forward.

### 2. Create the launchd plist

Create `~/Library/LaunchAgents/com.argylebits.gump.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.argylebits.gump</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/gump</string>
        <string>run</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/gump.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/gump.err</string>
</dict>
</plist>
```

All configuration is read from `~/.gump/config.yaml`.

### 3. Load the service

```bash
launchctl load ~/Library/LaunchAgents/com.argylebits.gump.plist
```

### 4. Verify it's running

```bash
launchctl list | grep gump
tail -f /tmp/gump.log
```

### 5. Managing the service

```bash
# Stop
launchctl unload ~/Library/LaunchAgents/com.argylebits.gump.plist

# Restart (unload then load)
launchctl unload ~/Library/LaunchAgents/com.argylebits.gump.plist
launchctl load ~/Library/LaunchAgents/com.argylebits.gump.plist

# View logs
tail -f /tmp/gump.log
tail -f /tmp/gump.err
```

## Workflow Configuration

Gump runs any GitHub Actions workflow — it's language-agnostic. Just set `runs-on: [self-hosted, linux]`.

The `gump-runner:latest` image has Swift pre-installed:

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

### Update Gump

```bash
cd /path/to/Gump
git pull
swift build -c release
sudo cp .build/release/gump /usr/local/bin/gump
# Restart the service if running via launchd
launchctl unload ~/Library/LaunchAgents/com.argylebits.gump.plist
launchctl load ~/Library/LaunchAgents/com.argylebits.gump.plist
```

### Update the runner image (new Swift version, etc.)

```bash
cd /path/to/Gump/images
container build --no-cache -t gump-runner:latest -f Containerfile -m 4G .
# Restart gump — the next container will use the new image
```

#### Keeping the image up to date

The `gump-runner:latest` image pins to `swiftly install latest` and the latest `actions/runner` at build time. Options for staying current:

- **Manual rebuild** — run `container build --no-cache ...` when you want a new Swift version. Simplest approach; Swift releases are infrequent.
- **Scheduled rebuild** — create a cron job or launchd timer that rebuilds the image weekly/monthly.
- **Version pinning** — edit the Containerfile to pin specific Swift and runner versions, update intentionally.

The image only needs rebuilding when Swift releases a new version or `actions/runner` has a breaking change.

### Update the container system

Download the latest `container` CLI from https://github.com/apple/container/releases and reinstall.
