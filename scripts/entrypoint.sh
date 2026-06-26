#!/bin/bash
set -e

chmod 666 /dev/uinput 2>/dev/null || true
# uhid is needed by Sunshine v2026+ (inputtino) for DS5/DS4 virtual gamepad creation.
# Without it: "Gamepad ds5 is disabled due to Permission denied" at startup and
# NO virtual controller is created at all (blocking even x360 emulation).
chmod 666 /dev/uhid 2>/dev/null || true

# Fix render device permissions: host and container render GIDs differ, so
# chmod 666 to make renderD* and card* accessible regardless of GID mapping.
chmod 666 /dev/dri/render* /dev/dri/card* 2>/dev/null || true

# nvidia-cap1 is root-only by default (cr--------); lizard needs it for NVENC
# capability probing. nvidia-cap2 (monitor) is already world-readable.
chmod 666 /dev/nvidia-caps/nvidia-cap1 2>/dev/null || true

# Create lizard user if it doesn\'t exist (preserve existing user if present)
if ! id -u lizard >/dev/null 2>&1; then
    # If video, render, input groups don\'t exist, create them
    # They may already exist but be empty, so we always recreate them to ensure lizard is added
    for group in video render input; do
        if ! getent group $group >/dev/null 2>&1; then
            groupadd $group
        fi
    done
    useradd -m -s /bin/bash lizard
    # Add lizard to required groups
    usermod -aG video,render,input lizard
    echo "Created lizard user with video, render, input groups"
fi

export XDG_RUNTIME_DIR=/tmp/runtime-lizard
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
chown lizard:lizard "$XDG_RUNTIME_DIR"

# Always refresh sunshine.conf from the image so CI changes take effect,
# while sunshine_state.json and credentials/ (paired devices) persist in the volume.
mkdir -p /home/lizard/.config/sunshine
cp /scripts/sunshine.conf /home/lizard/.config/sunshine/sunshine.conf
chown lizard:lizard /home/lizard/.config/sunshine/sunshine.conf
# apps.json is written by Sunshine when apps are modified via web UI (v2026+).
# The volume-persisted copy is root-owned from first-run Docker init; fix it.
chown lizard:lizard /home/lizard/.config/sunshine/apps.json 2>/dev/null || true

echo "Cleaning up existing display and socket files..."
pkill -f Xvfb 2>/dev/null || true
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true
rm -f /tmp/pulse-socket 2>/dev/null || true

# Ensure scraped-media directory exists with proper permissions
mkdir -p /home/lizard/ES-DE/downloaded_media
chown -R lizard:lizard /home/lizard/ES-DE/downloaded_media 2>/dev/null || true

export ROMPATH=/roms
export EMULATOR_RETROARCH=/usr/bin/retroarch
export CORE_RETROARCH=/usr/lib/x86_64-linux-gnu/libretro
export STARTDIR=/opt/es-de/usr/bin

mkdir -p /home/lizard/ES-DE/custom_systems
chown -R lizard:lizard /home/lizard/ES-DE/custom_systems 2>/dev/null || true

AS_LIZARD="runuser -u lizard --preserve-environment --"
echo "Starting dbus..."
mkdir -p /run/dbus
rm -f /run/dbus/pid
dbus-daemon --system --fork 2>/dev/null || true
export DBUS_SESSION_BUS_ADDRESS=$(
    $AS_LIZARD dbus-daemon --session --fork --print-address 2>/dev/null
) || true

# Pre-create cache dirs as root then chown, so mesa_shader_cache is never root-owned
mkdir -p /home/lizard/.cache/mesa_shader_cache
chown -R lizard:lizard /home/lizard/.cache
$AS_LIZARD mkdir -p /home/lizard/.config/pulse 2>/dev/null || true

echo "Starting PulseAudio..."
rm -f /tmp/pulse-socket /tmp/runtime-lizard/pulse/pid 2>/dev/null || true
$AS_LIZARD bash -c "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS} XDG_RUNTIME_DIR=/tmp/runtime-lizard pulseaudio --daemonize=no --exit-idle-time=-1 --load=module-null-sink --load=module-native-protocol-unix 2>&1" &
PULSE_PID=$!

for i in $(seq 1 10); do
    if [ -S /tmp/runtime-lizard/pulse/native ]; then
        echo "PulseAudio socket ready at /tmp/runtime-lizard/pulse/native"
        break
    fi
    sleep 0.5
done

echo "Starting Xvfb on display :99"
$AS_LIZARD Xvfb :99 -screen 0 1920x1080x24 +extension GLX +render     -nolisten tcp     -dpi 96 &
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

mkdir -p /home/lizard/ES-DE/custom_systems

echo "Starting input-watcher..."
/usr/local/bin/input-watcher.sh &
INPUT_WATCHER_PID=$!

echo "Starting recent-games-daemon..."
nohup /usr/local/bin/recent-games-daemon.sh > /dev/null 2>&1 &
RECENT_GAMES_PID=$!

echo "Starting ES-DE..."
nohup /usr/local/bin/launch-es-de.sh > /tmp/es-de.log 2>&1 &
ES_DE_PID=$!

SUNSHINE_PID=""

_cleanup() {
    echo "[entrypoint] Cleaning up processes..."
    kill $SUNSHINE_PID 2>/dev/null || true
    kill $INPUT_WATCHER_PID 2>/dev/null || true
    kill $RECENT_GAMES_PID 2>/dev/null || true
    exit 0
}
trap '_cleanup' SIGTERM SIGINT

echo "Starting Sunshine..."
while true; do
    $AS_LIZARD sunshine &
    SUNSHINE_PID=$!
    { wait $SUNSHINE_PID; exit_code=$?; } || true
    echo "[entrypoint] Sunshine exited (code $exit_code), restarting in 2s..."
    sleep 2
done
