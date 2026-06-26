#!/bin/bash
# input-watcher.sh — Monitor /sys/devices/virtual/input/ for Sunshine virtual
# devices and create missing /dev/input/ device nodes (eventX, jsX).
#
# /dev is a host bind mount, so nodes from previous sessions persist across
# container restarts. We clean stale nodes at startup and after each poll
# cycle so RetroArch always sees fresh, correct major:minor mappings.

INTERVAL=2

mkdir -p /dev/input

# Remove any /dev/input/event* or js* node whose major:minor no longer
# matches an active sysfs virtual input sub-device.
cleanup_stale_nodes() {
    for path in /dev/input/event* /dev/input/js*; do
        [ -e "$path" ] || continue
        local node="${path##*/}"
        # Search sysfs for a virtual device that owns this node name
        local found=0
        for input_dir in /sys/devices/virtual/input/input*; do
            [ -d "$input_dir/$node" ] && { found=1; break; }
        done
        if [ "$found" = "0" ]; then
            echo "input-watcher: Removing stale node $path"
            rm -f "$path"
        fi
    done
}

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
    cleanup_stale_nodes
    create_missing_nodes
    sleep "$INTERVAL"
done
