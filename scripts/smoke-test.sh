#!/bin/bash
# smoke-test.sh - Automated smoke tests for retroshine container
# Run AFTER container is started: bash smoke-test.sh

FAIL=0

echo "=== RetroShine Smoke Tests ==="
echo ""

# 1. Container running
docker ps --format '{{.Names}}' | grep -q retro-shine && \
    echo "✅ Container running" || { echo "❌ Container not running"; FAIL=1; }

# 2. Sunshine process alive
docker exec retro-shine pgrep sunshine > /dev/null && \
    echo "✅ Sunshine process running" || { echo "❌ Sunshine not running"; FAIL=1; }

# 3. Xvfb running
docker exec retro-shine pgrep Xvfb > /dev/null && \
    echo "✅ Xvfb running" || { echo "❌ Xvfb not running"; FAIL=1; }

# 4. Sunshine Web UI reachable
curl -sk https://localhost:47990 > /dev/null 2>&1 && \
    echo "✅ Sunshine Web UI reachable" || { echo "❌ Web UI not reachable"; FAIL=1; }

# 5. Encoder configured (VAAPI or NVENC)
docker exec retro-shine grep -Eq "encoder = (vaapi|nvenc)" /config/sunshine.conf && \
    echo "✅ $(docker exec retro-shine grep -oP 'encoder = \K\w+' /config/sunshine.conf) configured" || { echo "❌ Encoder not configured"; FAIL=1; }

# 6. ES-DE installed
docker exec retro-shine which es-de > /dev/null && \
    echo "✅ ES-DE installed" || { echo "❌ ES-DE missing"; FAIL=1; }

# 7. RetroArch installed
docker exec retro-shine which retroarch > /dev/null && \
    echo "✅ RetroArch installed" || { echo "❌ RetroArch missing"; FAIL=1; }

# 8. RetroArch cores present
CORE_DIR="/usr/lib/x86_64-linux-gnu/libretro"
CORE_COUNT=$(docker exec retro-shine sh -c 'ls -1 /usr/lib/x86_64-linux-gnu/libretro/*.so 2>/dev/null' | wc -l)
if [ "$CORE_COUNT" -ge 4 ]; then
    echo "✅ $CORE_COUNT RetroArch cores found"
else
    echo "❌ Only $CORE_COUNT cores (need 4+)"
    FAIL=1
fi

# 9. uinput available
docker exec retro-shine test -c /dev/uinput && \
    echo "✅ uinput available" || { echo "❌ uinput missing"; FAIL=1; }

# 10. NVIDIA GPU detected
docker exec retro-shine nvidia-smi -L 2>/dev/null | grep -q "Quadro P1000" && \
    echo "✅ NVIDIA Quadro P1000 detected" || { echo "❌ NVIDIA GPU not detected"; FAIL=1; }

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 All smoke tests passed!"
else
    echo "❌ $FAIL test(s) failed — see above"
    exit 1
fi
