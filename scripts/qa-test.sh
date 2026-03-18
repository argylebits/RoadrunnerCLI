#!/bin/bash
set -euo pipefail

# Manual QA test script for Roadrunner CLI
# Run from repo root: ./scripts/qa-test.sh
#
# Uses ROADRUNNER_HOME pointed at a temp directory so nothing touches
# your real ~/.roadrunner or LaunchAgents.
# Requires: swift build to have been run first.

BINARY="$(pwd)/.build/debug/roadrunner"
TEMP_DIR=$(mktemp -d)
export ROADRUNNER_HOME="$TEMP_DIR/.roadrunner"
PASS=0
FAIL=0

cleanup() {
    rm -rf "$TEMP_DIR"
    echo ""
    echo "================================"
    echo "Results: $PASS passed, $FAIL failed"
    echo "================================"
    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
}
trap cleanup EXIT

pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
    if [ -n "${2:-}" ]; then
        echo "        $2"
    fi
}

check_contains() {
    local output="$1"
    local expected="$2"
    local label="$3"
    if echo "$output" | grep -qF -- "$expected"; then
        pass "$label"
    else
        fail "$label" "expected to contain: $expected"
    fi
}

check_not_contains() {
    local output="$1"
    local expected="$2"
    local label="$3"
    if echo "$output" | grep -qF -- "$expected"; then
        fail "$label" "should not contain: $expected"
    else
        pass "$label"
    fi
}

check_exit_code() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    if [ "$actual" -eq "$expected" ]; then
        pass "$label"
    else
        fail "$label" "expected exit $expected, got $actual"
    fi
}

echo "Building..."
swift build -q 2>&1
echo "Using ROADRUNNER_HOME=$ROADRUNNER_HOME"
echo ""

# ============================================================
echo "== 1. Help & Version =="
# ============================================================

OUTPUT=$("$BINARY" --help 2>&1)
check_contains "$OUTPUT" "roadrunner" "help shows command name"
check_contains "$OUTPUT" "init" "help lists init subcommand"
check_contains "$OUTPUT" "run-once" "help lists run-once subcommand"
check_contains "$OUTPUT" "run " "help lists run subcommand"
check_contains "$OUTPUT" "service" "help lists service subcommand"
check_contains "$OUTPUT" "version" "help lists --version flag"

OUTPUT=$("$BINARY" --version 2>&1)
if [ -n "$OUTPUT" ]; then
    pass "version outputs something: $OUTPUT"
else
    fail "version outputs something"
fi

# ============================================================
echo ""
echo "== 2. Init (non-interactive with flags) =="
# ============================================================

# Create a fake private key so init doesn't reject it
echo "fake-key" > "$TEMP_DIR/test-key.pem"

OUTPUT=$("$BINARY" init \
    --app-id 12345 \
    --installation-id 67890 \
    --private-key "$TEMP_DIR/test-key.pem" \
    --url "https://github.com/test-org" \
    --image "ghcr.io/argylebits/roadrunner:latest" \
    --labels "self-hosted,linux" \
    --cpus 2 \
    --memory 4096 \
    --no-alias \
    2>&1)

check_contains "$OUTPUT" "Config written" "init reports config written"

CONFIG_PATH="$ROADRUNNER_HOME/config.yaml"
if [ -f "$CONFIG_PATH" ]; then
    pass "config file created"
else
    fail "config file created at $CONFIG_PATH"
fi

if [ -f "$CONFIG_PATH" ]; then
    CONFIG=$(cat "$CONFIG_PATH")
    check_contains "$CONFIG" "app-id: 12345" "config contains app-id"
    check_contains "$CONFIG" "installation-id: 67890" "config contains installation-id"
    check_contains "$CONFIG" "private-key: $TEMP_DIR/test-key.pem" "config contains private-key"
    check_contains "$CONFIG" "url: https://github.com/test-org" "config contains url"
    check_contains "$CONFIG" "image: ghcr.io/argylebits/roadrunner:latest" "config contains image"
    check_contains "$CONFIG" "labels: self-hosted,linux" "config contains labels"
    check_contains "$CONFIG" "cpus: 2" "config contains cpus"
    check_contains "$CONFIG" "memory: 4096" "config contains memory"
    check_contains "$CONFIG" "Roadrunner" "config header says Roadrunner"
    check_not_contains "$CONFIG" "Gump" "config has no Gump references"
fi

# ============================================================
echo ""
echo "== 3. Init --force overwrites =="
# ============================================================

OUTPUT=$("$BINARY" init \
    --app-id 99999 \
    --installation-id 11111 \
    --private-key "$TEMP_DIR/test-key.pem" \
    --url "https://github.com/other-org" \
    --no-alias \
    --force \
    2>&1)

check_contains "$OUTPUT" "Config written" "init --force overwrites"
CONFIG=$(cat "$CONFIG_PATH")
check_contains "$CONFIG" "app-id: 99999" "overwritten config has new app-id"

# ============================================================
echo ""
echo "== 4. Init refuses overwrite without --force =="
# ============================================================

set +e
OUTPUT=$("$BINARY" init \
    --app-id 11111 \
    --installation-id 22222 \
    --private-key "$TEMP_DIR/test-key.pem" \
    --url "https://github.com/test-org" \
    --no-alias \
    2>&1)
EXIT=$?
set -e

check_exit_code "$EXIT" 1 "init refuses overwrite without --force"
check_contains "$OUTPUT" "already exists" "init shows already exists message"

# ============================================================
echo ""
echo "== 5. Init rejects bad URL =="
# ============================================================

set +e
OUTPUT=$("$BINARY" init \
    --app-id 11111 \
    --installation-id 22222 \
    --private-key "$TEMP_DIR/test-key.pem" \
    --url "https://gitlab.com/test" \
    --no-alias \
    --force \
    2>&1)
EXIT=$?
set -e

check_exit_code "$EXIT" 1 "init rejects non-GitHub URL"

# ============================================================
echo ""
echo "== 6. Init rejects missing private key =="
# ============================================================

set +e
OUTPUT=$("$BINARY" init \
    --app-id 11111 \
    --installation-id 22222 \
    --private-key "/nonexistent/key.pem" \
    --url "https://github.com/test-org" \
    --no-alias \
    --force \
    2>&1)
EXIT=$?
set -e

check_exit_code "$EXIT" 1 "init rejects missing private key"
check_contains "$OUTPUT" "not found" "init shows file not found"

# ============================================================
echo ""
echo "== 7. Service install requires config =="
# ============================================================

# Remove config
rm -f "$CONFIG_PATH"

set +e
OUTPUT=$("$BINARY" service install 2>&1)
EXIT=$?
set -e

check_exit_code "$EXIT" 1 "install fails without config"
check_contains "$OUTPUT" "roadrunner init" "install suggests init"

# ============================================================
echo ""
echo "== 8. Service lifecycle =="
# ============================================================

# Recreate config for service tests
"$BINARY" init \
    --app-id 12345 \
    --installation-id 67890 \
    --private-key "$TEMP_DIR/test-key.pem" \
    --url "https://github.com/test-org" \
    --no-alias \
    2>&1 > /dev/null

# Status when not installed
OUTPUT=$("$BINARY" service status 2>&1)
check_contains "$OUTPUT" "Not installed" "status shows not installed"

# Install
OUTPUT=$("$BINARY" service install 2>&1)
check_contains "$OUTPUT" "Service installed" "service install succeeds"

PLIST_PATH="$HOME/Library/LaunchAgents/com.argylebits.roadrunner.plist"
if [ -f "$PLIST_PATH" ]; then
    pass "plist file created"
    PLIST=$(cat "$PLIST_PATH")
    check_contains "$PLIST" "com.argylebits.roadrunner" "plist contains label"
    check_contains "$PLIST" "roadrunner" "plist contains binary reference"
    check_contains "$PLIST" "<string>run</string>" "plist contains run command"
    check_not_contains "$PLIST" "gump" "plist has no gump references"
else
    fail "plist file created at $PLIST_PATH"
fi

# Install again without --force should fail
set +e
OUTPUT=$("$BINARY" service install 2>&1)
EXIT=$?
set -e
check_exit_code "$EXIT" 1 "install refuses without --force"
check_contains "$OUTPUT" "--force" "install suggests --force"

# Install with --force
OUTPUT=$("$BINARY" service install --force 2>&1)
check_contains "$OUTPUT" "Service installed" "install --force succeeds"

# Restart
OUTPUT=$("$BINARY" service restart 2>&1)
check_contains "$OUTPUT" "restarted" "restart succeeds"

# Uninstall
OUTPUT=$("$BINARY" service uninstall 2>&1)
check_contains "$OUTPUT" "stopped and removed" "uninstall succeeds"

if [ -f "$PLIST_PATH" ]; then
    fail "plist removed after uninstall"
else
    pass "plist removed after uninstall"
fi

# Uninstall again should fail
set +e
OUTPUT=$("$BINARY" service uninstall 2>&1)
EXIT=$?
set -e
check_exit_code "$EXIT" 1 "uninstall fails when not installed"

# Restart when not installed should fail
set +e
OUTPUT=$("$BINARY" service restart 2>&1)
EXIT=$?
set -e
check_exit_code "$EXIT" 1 "restart fails when not installed"
