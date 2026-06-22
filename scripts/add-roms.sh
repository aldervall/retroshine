#!/bin/bash
# Usage: ./add-roms.sh <system> <rom-file>
# Example: ./add-roms.sh nes mygame.nes
# Adds ROM to build context, rebuilds Docker image, restarts container

set -e

SYSTEM=$1
ROM=$2

if [ -z "$SYSTEM" ] || [ -z "$ROM" ]; then
    echo "Usage: $0 <system> <rom-file>"
    echo "Systems: nes snes gb gba genesis"
    exit 1
fi

if [ ! -f "$ROM" ]; then
    echo "Error: ROM file '$ROM' not found"
    exit 1
fi

VALID_SYSTEMS="nes snes gb gba genesis"
if ! echo "$VALID_SYSTEMS" | grep -qw "$SYSTEM"; then
    echo "Error: Unknown system '$SYSTEM'"
    echo "Valid: $VALID_SYSTEMS"
    exit 1
fi

echo "Adding $ROM to $SYSTEM..."
cp "$ROM" "/opt/wolf-container/roms/$SYSTEM/"

echo "Rebuilding Docker image..."
cd /opt/wolf-container
docker compose build

echo "Restarting container..."
docker compose up -d

echo "Done! ROM added. Use Moonlight to launch ES-DE and play."
