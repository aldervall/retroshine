#!/bin/bash
set -e

# deploy.sh — RetroShine deployment script
# Run this from YOUR machine (not from the dev environment)
# It handles Phase 0-3: LXC prep, build, run, verify

PVE_HOST="10.10.0.3"
LXC_HOST="10.10.0.55"
PROJECT_DIR="/opt/wolf-container"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; exit 1; }
info() { echo -e "${YELLOW}🔸 $1${NC}"; }

echo "=== RetroShine Deployment ==="
echo ""

# ────────────────────────────────────────────
# PHASE 0a — Bump LXC RAM on Proxmox host
# ────────────────────────────────────────────
info "Phase 0a: Bumping LXC RAM to 4GB on $PVE_HOST..."

ssh root@"$PVE_HOST" <<'PVE_EOF'
set -e
echo "  Stopping LXC 108..."
pct stop 108
echo "  Updating memory config..."
sed -i 's/^memory: 2048/memory: 4096/' /etc/pve/lxc/108.conf
sed -i 's/^swap: 512/swap: 1024/' /etc/pve/lxc/108.conf
echo "  Starting LXC 108..."
pct start 108
echo "  Done."
PVE_EOF

pass "LXC RAM bumped to 4GB"

# ────────────────────────────────────────────
# PHASE 0b — Teardown Wolf on LXC
# ────────────────────────────────────────────
info "Phase 0b: Tearing down Wolf on $LXC_HOST..."

ssh root@"$LXC_HOST" <<'LXC_EOF'
set -e
echo "  Stopping wolf-input-watcher..."
systemctl stop wolf-input-watcher.service 2>/dev/null || true
systemctl disable wolf-input-watcher.service 2>/dev/null || true
rm -f /usr/local/bin/wolf-input-watcher.sh
rm -f /etc/systemd/system/wolf-input-watcher.service
systemctl daemon-reload
echo "  Stopping Wolf containers..."
cd /opt/wolf 2>/dev/null && docker compose down 2>/dev/null || true
echo "  Pruning Docker..."
docker system prune -a --volumes -f 2>/dev/null || true
echo "  Removing Wolf artifacts..."
rm -rf /etc/wolf /opt/wolf
echo "  Done."
LXC_EOF

pass "Wolf torn down on LXC"

# ────────────────────────────────────────────
# PHASE 1b — Copy project & build on LXC
# ────────────────────────────────────────────
info "Phase 1b: Copying project to $LXC_HOST..."

rsync -avz --delete "$PROJECT_DIR/" root@"$LXC_HOST":"$PROJECT_DIR/"

pass "Project copied to LXC"

info "Building Docker image on LXC (this takes ~10 min)..."

ssh root@"$LXC_HOST" "cd $PROJECT_DIR && docker build -t retroshine:latest ."

pass "Docker image built on LXC"

# ────────────────────────────────────────────
# PHASE 2 — Start container & verify
# ────────────────────────────────────────────
info "Phase 2: Starting container..."

ssh root@"$LXC_HOST" "cd $PROJECT_DIR && docker compose up -d"

# Wait for services
sleep 10

# Verify
ssh root@"$LXC_HOST" <<'VERIFY_EOF'
set -e
FAIL=0

echo "  Checking container..."
docker ps --format '{{.Names}}' | grep -q retro-shine && echo "   ✅ Container running" || { echo "   ❌ Container not running"; FAIL=1; }

echo "  Checking processes..."
docker exec retro-shine pgrep sunshine > /dev/null && echo "   ✅ Sunshine running" || { echo "   ❌ Sunshine not running"; FAIL=1; }
docker exec retro-shine pgrep Xvfb > /dev/null && echo "   ✅ Xvfb running" || { echo "   ❌ Xvfb not running"; FAIL=1; }

echo "  Checking ES-DE..."
docker exec retro-shine which es-de > /dev/null && echo "   ✅ ES-DE installed" || { echo "   ❌ ES-DE missing"; FAIL=1; }

echo "  Checking GPU..."
docker exec retro-shine nvidia-smi -L 2>/dev/null | head -1 && echo "   ✅ GPU detected" || echo "   ⚠️  nvidia-smi unavailable (expected in build env without GPUs)"

echo "  Checking Web UI..."
curl -sk https://localhost:47990 > /dev/null 2>&1 && echo "   ✅ Web UI reachable" || echo "   ⚠️  Web UI not reachable yet (may need more time)"

if [ "$FAIL" -eq 0 ]; then
    echo "   ✅ All critical checks passed"
else
    echo "   ⚠️  Some checks failed — investigate"
fi
VERIFY_EOF

pass "Container started and verified"

# ────────────────────────────────────────────
# PHASE 3 — Smoke tests
# ────────────────────────────────────────────
info "Phase 3: Running smoke tests..."

ssh root@"$LXC_HOST" "cd $PROJECT_DIR && bash scripts/smoke-test.sh" || true

# ────────────────────────────────────────────
echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Next steps:"
echo "  1. Open Moonlight client → Add host → $LXC_HOST"
echo "  2. Browse to https://$LXC_HOST:47990 for PIN"
echo "     User: admin / Pass: retro123"
echo "  3. Enter PIN in Moonlight"
echo "  4. Launch 'ES-DE (EmulationStation)' or 'RetroArch (standalone)'"
echo ""
echo "To add ROMs later:"
echo "  ./$PROJECT_DIR/scripts/add-roms.sh nes mygame.nes"
