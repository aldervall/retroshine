#!/bin/bash
# input-watcher.sh — Monitor /sys/devices/virtual/input/ for Sunshine virtual
# gamepads and create missing /dev/input/ device nodes (eventX, jsX).
#
# Without udev inside Docker, uinput
# devices get registered in the kernel but no /dev/input/event* or /dev/input/js*
# nodes are created. SDL needs these nodes to detect joysticks.
#
# Poll every 2 seconds (low overhead, just stat + read).

INTERVAL=2

# Maps inputN to its event minor and js minor by reading sysfs
create_missing_nodes() {
    # Find Sunshine virtual gamepads
    for input_dir in /sys/devices/virtual/input/input*; do
        [ -d "$input_dir" ] || continue
        input_num="${input_dir##*/input}"

        name=$(cat "$input_dir/name" 2>/dev/null)
        # Only care about Sunshine gamepads
        case "$name" in
            *"Sunshine"*"pad"*|*"Nintendo"*)
                ;;
            *)
                continue
                ;;
        esac

        # Create event node if missing
        for event_dir in "$input_dir"/event*; do
            [ -d "$event_dir" ] || continue
            IFS=':' read -r major minor < "$event_dir/dev" 2>/dev/null
            event_num="${event_dir##*/event}"
            event_dev="/dev/input/event${event_num}"
            if [ ! -e "$event_dev" ]; then
                mknod -m 666 "$event_dev" c "$major" "$minor" 2>/dev/null
                echo "input-watcher: created $event_dev ($major:$minor) for '$name'"
            fi
        done

        # Create js node if missing
        for js_dir in "$input_dir"/js*; do
            [ -d "$js_dir" ] || continue
            js_num="${js_dir##*/js}"
            IFS=':' read -r major minor < "$js_dir/dev" 2>/dev/null
            js_dev="/dev/input/js${js_num}"
            if [ ! -e "$js_dev" ]; then
                mknod -m 666 "$js_dev" c "$major" "$minor" 2>/dev/null
                echo "input-watcher: created $js_dev ($major:$minor) for '$name'"
            fi
        done
    done

    # Also handle Sunshine mouse/keyboard passthrough devices:
    #   Mouse passthrough, Keyboard passthrough, Touch passthrough
    # These also need event nodes for SDL hotplug if apps read them.
    for input_dir in /sys/devices/virtual/input/input*; do
        [ -d "$input_dir" ] || continue
        name=$(cat "$input_dir/name" 2>/dev/null)
        case "$name" in
            *"passthrough"*)
                # Some passthrough devices don't have event child on older Sunshine
                # Just create if event dir exists
                for event_dir in "$input_dir"/event*; do
                    [ -d "$event_dir" ] || continue
                    IFS=':' read -r major minor < "$event_dir/dev" 2>/dev/null
                    event_num="${event_dir##*/event}"
                    event_dev="/dev/input/event${event_num}"
                    if [ ! -e "$event_dev" ]; then
                        mknod -m 666 "$event_dev" c "$major" "$minor" 2>/dev/null
                        echo "input-watcher: created $event_dev ($major:$minor) for '$name'"
                    fi
                done
                ;;
        esac
    done
}

echo "input-watcher: started, polling every ${INTERVAL}s"

while true; do
    create_missing_nodes
    sleep "$INTERVAL"
done
