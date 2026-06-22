#!/bin/bash
# Wait for a Sunshine virtual gamepad device node to appear, then launch ES-DE.
set -e

GAMEPAD_WAIT_TIMEOUT=15
echo "launch-es-de: Waiting up to ${GAMEPAD_WAIT_TIMEOUT}s for gamepad device..."

for i in $(seq 1 $GAMEPAD_WAIT_TIMEOUT); do
    for js_dev in /dev/input/js*; do
        if [ -e "$js_dev" ]; then
            echo "launch-es-de: Found gamepad at $js_dev"
            break 2
        fi
    done
    sleep 1
done

if ! ls /dev/input/js* >/dev/null 2>&1; then
    echo "launch-es-de: No gamepad detected after ${GAMEPAD_WAIT_TIMEOUT}s, launching anyway"
fi

echo "launch-es-de: Starting ES-DE..."
exec es-de --no-splash
