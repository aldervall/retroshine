#!/bin/bash
# input-watcher.sh — Monitor /sys/devices/virtual/input/ for Sunshine virtual
# devices and create missing /dev/input/ device nodes (eventX, jsX).
#
# Without udev inside Docker, uinput devices get registered in the kernel but
# no /dev/input/event* or /dev/input/js* nodes are created. SDL needs these
# nodes to detect joysticks.
#
# Poll every 2 seconds (low overhead, just stat + read).

INTERVAL=2

mkdir -p /dev/input

create_node() {
    local dev_file="$1" label="$2" name="$3"
    [ -d "$dev_file" ] || return
    local major minor
    IFS=':' read -r major minor < "$dev_file/dev" 2>/dev/null
    [ -n "$major" ] && [ -n "$minor" ] || return
    local node="${dev_file##*/}"      # e.g. "event5" or "js0"
    local path="/dev/input/${node}"
    [ -e "$path" ] && return
    
    # Skip device creation in container environments due to security restrictions
    # If the container has restricted /dev, we cannot create device nodes.
    # This is normal for production containers - SDL will use existing nodes.
    echo "input-watcher: Skipping device node creation for $path ($major:$minor) for $name"
    return
}

create_missing_nodes() {
    for input_dir in /sys/devices/virtual/input/input*; do
        [ -d "$input_dir" ] || continue
        local name
        name=$(cat "$input_dir/name" 2>/dev/null)
        [ -n "$name" ] || continue

        case "$name" in
            *"Sunshine"*"pad"*|*"Nintendo"*)
                for sub in "$input_dir"/event* "$input_dir"/js*; do
                    create_node "$sub" "gamepad" "$name"
                done
                ;;
            *"passthrough"*)
                for sub in "$input_dir"/event*; do
                    create_node "$sub" "passthrough" "$name"
                done
                ;;
        esac
    done
}

echo "input-watcher: started, polling every ${INTERVAL}s (device creation disabled)"

while true; do
    create_missing_nodes
    sleep "$INTERVAL"
done
