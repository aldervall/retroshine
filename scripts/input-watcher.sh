#!/bin/bash
# input-watcher.sh — Monitor /sys/devices/virtual/input/ for Sunshine virtual
# devices and create missing /dev/input/ device nodes (eventX, jsX).
#
# Stale node cleanup is done ONCE at container startup by entrypoint.sh.
# This script only CREATES nodes — never removes them mid-session — so
# RetroArch cannot lose an open device file while a game is running.

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

while true; do
    create_missing_nodes
    sleep "$INTERVAL"
done
