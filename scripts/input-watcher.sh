#!/bin/bash
# input-watcher.sh — Monitor /sys/devices/virtual/input/ for Sunshine virtual
# devices and create missing /dev/input/ device nodes (eventX, jsX).
#
# Stale node cleanup is done ONCE at container startup by entrypoint.sh.
# This script only CREATES nodes — never removes them mid-session — so
# RetroArch cannot lose an open device file while a game is running.
#
# Reconnect delay: when Sunshine virtual devices disappear (Moonlight disconnect),
# we delay creating nodes for newly-appearing devices by 2 seconds. This gives
# SDL2 time to process the JOYDEVICEREMOVED event before JOYDEVICEADDED fires,
# preventing a RetroArch 1.18.0 use-after-free crash in the hotplug handler.
# SDL2 processes REMOVED within one frame (~16ms), so 2s is a 120x safety margin.

INTERVAL=2

mkdir -p /dev/input

create_node() {
    local dev_file="$1" name="$2"
    [ -d "$dev_file" ] || return
    local major minor
    IFS=':' read -r major minor < "$dev_file/dev" 2>/dev/null
    [ -n "$major" ] && [ -n "$minor" ] || return
    local node="${dev_file##*/}"
    local path="/dev/input/${node}"
    [ -e "$path" ] && return
    echo "input-watcher: Creating $path ($major:$minor) for [$name]"
    mknod -m 666 "$path" c "$major" "$minor"
}

count_sunshine_devices() {
    local count=0
    for d in /sys/devices/virtual/input/input*; do
        [ -d "$d" ] || continue
        local name
        name=$(cat "$d/name" 2>/dev/null)
        case "$name" in Sunshine*) count=$((count + 1)) ;; esac
    done
    echo "$count"
}

create_missing_nodes() {
    for input_dir in /sys/devices/virtual/input/input*; do
        [ -d "$input_dir" ] || continue
        local name
        name=$(cat "$input_dir/name" 2>/dev/null)
        [ -n "$name" ] || continue
        for sub in "$input_dir"/event* "$input_dir"/js*; do
            create_node "$sub" "$name"
        done
    done
}

echo "input-watcher: started, polling every ${INTERVAL}s"

LAST_SUNSHINE_COUNT=0
RECONNECT_DELAY_UNTIL=0

while true; do
    current_time=$(date +%s)
    sunshine_count=$(count_sunshine_devices)

    # Detect Sunshine device disappearance (Moonlight disconnect / reconnect)
    if [ "$LAST_SUNSHINE_COUNT" -gt 0 ] && [ "$sunshine_count" -lt "$LAST_SUNSHINE_COUNT" ]; then
        RECONNECT_DELAY_UNTIL=$((current_time + 2))
        echo "input-watcher: Sunshine devices dropped ($LAST_SUNSHINE_COUNT→$sunshine_count), delaying node creation 2s to let SDL2 process JOYDEVICEREMOVED first"
    fi
    LAST_SUNSHINE_COUNT=$sunshine_count

    # During the reconnect delay, skip node creation so SDL2 sees REMOVED before ADDED
    if [ "$current_time" -lt "$RECONNECT_DELAY_UNTIL" ]; then
        remaining=$((RECONNECT_DELAY_UNTIL - current_time))
        echo "input-watcher: reconnect delay active, ${remaining}s remaining"
        sleep "$INTERVAL"
        continue
    fi

    create_missing_nodes
    sleep "$INTERVAL"
done
