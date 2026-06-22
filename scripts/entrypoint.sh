#!/bin/bash
set -e

chmod 666 /dev/uinput 2>/dev/null || true
usermod -aG video,render,input lizard 2>/dev/null || true

export XDG_RUNTIME_DIR=/tmp/runtime-lizard
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
chown lizard:lizard "$XDG_RUNTIME_DIR"

echo "Cleaning up existing display and socket files..."
pkill -f Xvfb 2>/dev/null || true
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true
rm -f /tmp/pulse-socket 2>/dev/null || true

AS_LIZARD="runuser -u lizard --preserve-environment --"

echo "Starting PulseAudio..."
rm -f /tmp/pulse-socket /tmp/runtime-lizard/pulse/pid 2>/dev/null || true
$AS_LIZARD bash -c 'XDG_RUNTIME_DIR=/tmp/runtime-lizard pulseaudio --daemonize=no --exit-idle-time=-1 --load=module-null-sink --load=module-native-protocol-unix 2>&1' &
PULSE_PID=$!

for i in $(seq 1 10); do
    if [ -S /tmp/runtime-lizard/pulse/native ]; then
        echo "PulseAudio socket ready at /tmp/runtime-lizard/pulse/native"
        break
    fi
    sleep 0.5
done

echo "Starting Xvfb on display :99"
$AS_LIZARD Xvfb :99 -screen 0 1920x1080x24 +extension GLX +render \
    -nolisten tcp \
    -dpi 96 &
XVFB_PID=$!

for i in $(seq 1 10); do
    if xdpyinfo -display :99 >/dev/null 2>&1; then
        echo "Xvfb ready on :99"
        break
    fi
    sleep 0.5
done

if ! xdpyinfo -display :99 >/dev/null 2>&1; then
    echo "ERROR: Xvfb failed to start"
    exit 1
fi

# Auto-set credentials if state file doesn't exist (first start without persisted state)
if [ ! -f /home/lizard/.config/sunshine/sunshine_state.json ]; then
    echo "Setting default credentials (admin/retro123)..."
    $AS_LIZARD sunshine --creds "$SUNSHINE_USER" "$SUNSHINE_PASS" 2>&1 | grep -v "config: '"
    echo "Credentials set."
fi

# Start input-watcher to create device nodes for Sunshine virtual gamepads
# (no udev inside container means uinput devices lack /dev/input/event* nodes)
echo "Starting input-watcher..."
/usr/local/bin/input-watcher.sh &
INPUT_WATCHER_PID=$!

echo "Starting Sunshine..."
$AS_LIZARD sunshine &
SUNSHINE_PID=$!
trap 'kill $SUNSHINE_PID; kill $INPUT_WATCHER_PID 2>/dev/null; exit 0' SIGTERM SIGINT
wait $SUNSHINE_PID
