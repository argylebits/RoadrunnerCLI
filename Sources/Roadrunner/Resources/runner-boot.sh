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
