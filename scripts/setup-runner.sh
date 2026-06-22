#!/bin/bash
set -e

# setup-runner.sh — Register this server as a self-hosted GitHub Actions runner
# Run this AFTER Tailscale is connected and you have a GitHub token.
#
# Usage: GITHUB_TOKEN=ghp_xxx bash scripts/setup-runner.sh
#        (get token from: https://github.com/settings/tokens → repo scope)

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
pass() { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; exit 1; }

REPO="aldervall/retroshine"
RUNNER_DIR="/opt/actions-runner"

if [ -z "$GITHUB_TOKEN" ]; then
    fail "GITHUB_TOKEN not set. Usage: GITHUB_TOKEN=ghp_xxx bash $0"
fi

echo "=== RetroShine — GitHub Actions Runner Setup ==="
echo ""

# Check disk space
echo "Checking disk space..."
AVAIL=$(df / | tail -1 | awk '{print $4}')
if [ "$AVAIL" -lt 500000 ]; then
    fail "Less than 500MB free. Need ~300MB for runner."
fi
pass "Disk space OK"

# Create runner directory
echo "Creating runner directory..."
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# Download latest runner
echo "Downloading GitHub Actions runner..."
curl -fsSL -o actions-runner.tar.gz \
    "https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64-2.322.0.tar.gz"

echo "Extracting..."
tar xzf actions-runner.tar.gz
rm -f actions-runner.tar.gz
pass "Runner downloaded and extracted"

# Configure
echo "Configuring runner..."
./config.sh --url "https://github.com/$REPO" \
    --token "$GITHUB_TOKEN" \
    --name "retro-shine" \
    --labels "self-hosted,retroshine" \
    --unattended \
    --replace

pass "Runner configured"

# Install as service
echo "Installing as systemd service..."
./svc.sh install
./svc.sh start
pass "Runner service installed and started"

# Verify
echo "Verifying..."
sleep 3
systemctl status actions.runner.$REPO.retro-shine.service --no-pager | head -10
pass "Runner is running"

echo ""
echo "=== Setup Complete ==="
echo "Runner is registered for $REPO as 'retro-shine'"
echo "Labels: self-hosted, retroshine"
echo ""
echo "Next steps:"
echo "  1. Push a version tag to trigger deployment:"
echo "     git tag -a v1.0.0 -m 'Release v1.0.0'"
echo "     git push origin master --tags"
echo "  2. Or trigger manually from GitHub Actions UI"
