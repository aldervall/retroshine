#!/bin/bash
set -euo pipefail

# ============================================================
# recent-games-daemon.sh
# Polls RetroArch content_history.lpl every 10s and generates
# Sunshine apps.json with the last 10 unique played games.
# Run as a background daemon inside the container.
# ============================================================

# --- Configuration -----------------------------------------------------------
HISTORY_FILE="/home/lizard/.config/retroarch/content_history.lpl"
APPS_FILE="/home/lizard/.config/sunshine/apps.json"
APPS_TMP="/home/lizard/.config/sunshine/apps.json.tmp"
ES_DE_MEDIA_BASE="/home/lizard/ES-DE/downloaded_media"
POLL_INTERVAL=10

# --- System prefix map -------------------------------------------------------
declare -A SYSTEM_PREFIX
SYSTEM_PREFIX[nes]="NES"
SYSTEM_PREFIX[snes]="SNES"
SYSTEM_PREFIX[gb]="Game Boy"
SYSTEM_PREFIX[gba]="Game Boy Advance"
SYSTEM_PREFIX[genesis]="Genesis"

# --- ES-DE base template (always present at index 0) ------------------------
ES_DE_BASE='{
  "apps": [
    {
      "name": "ES-DE (EmulationStation)",
      "cmd": "launch-es-de.sh",
      "image-path": "",
      "output": "",
      "index": 0
    }
  ],
  "env": {
    "DISPLAY": ":99",
    "PULSE_SERVER": "unix:/tmp/runtime-lizard/pulse/native",
    "XDG_RUNTIME_DIR": "/tmp/runtime-lizard",
    "SDL_AUDIODRIVER": "pulse"
  }
}'

# --- Helpers -----------------------------------------------------------------

# Atomic write of final JSON + SIGHUP Sunshine (only when content changes)
write_apps_json() {
  local entries_json="$1"
  local final_json game_count sun_pid new_hash old_hash

  game_count=$(echo "$entries_json" | jq 'length')

  final_json=$(echo "$ES_DE_BASE" | jq --argjson entries "$entries_json" \
    '.apps = .apps + $entries') || {
    echo "[recent-games] ERROR: Failed to build final apps.json"
    return 1
  }

  # Skip write and SIGHUP if content is identical to what's already on disk.
  # This prevents the "no history file" path from hammering Sunshine with
  # SIGHUP every 10 seconds when nothing has changed.
  new_hash=$(echo "$final_json" | jq -cS . | sha256sum)
  old_hash=$(jq -cS . "$APPS_FILE" 2>/dev/null | sha256sum || echo "")
  if [[ "$new_hash" == "$old_hash" ]]; then
    return 0
  fi

  # Ensure target directory exists
  mkdir -p "$(dirname "$APPS_FILE")"

  # Atomic write
  echo "$final_json" > "$APPS_TMP"
  mv "$APPS_TMP" "$APPS_FILE"

  echo "[recent-games] Updated apps.json with ${game_count} recent games"

  # SIGHUP Sunshine to reload apps
  sun_pid=$(pgrep sunshine | head -1) || true
  if [[ -n "$sun_pid" ]]; then
    kill -HUP "$sun_pid" 2>/dev/null || true
    echo "[recent-games] SIGHUP sent to Sunshine (PID: $sun_pid)"
  fi
}

# Strip known ROM file extensions
strip_extensions() {
  local name="$1"
  for ext in .nes .sfc .smc .gb .gba .gen .md .zip .7z; do
    name="${name%$ext}"
  done
  printf '%s' "$name"
}

# --- Main polling loop -------------------------------------------------------
last_mtime=0

while true; do
  if [[ ! -f "$HISTORY_FILE" ]]; then
    echo "[recent-games] No history file at $HISTORY_FILE, generating ES-DE-only config"
    write_apps_json "[]"
    sleep "$POLL_INTERVAL"
    continue
  fi

  current_mtime=$(stat -c %Y "$HISTORY_FILE" 2>/dev/null || echo "0")
  if [[ "$current_mtime" -eq "$last_mtime" ]]; then
    sleep "$POLL_INTERVAL"
    continue
  fi
  last_mtime="$current_mtime"

  # Validate JSON
  if ! jq . "$HISTORY_FILE" > /dev/null 2>&1; then
    echo "[recent-games] WARN: Invalid JSON in history file, skipping cycle"
    sleep "$POLL_INTERVAL"
    continue
  fi

  echo "[recent-games] Checking history file mtime..."

  declare -A seen_paths
  seen_paths=()
  entry_index=1
  all_entries="[]"

  # Read items (most-recent-first), deduplicate, build entries
  while IFS= read -r item_json; do
    [[ -z "$item_json" ]] && continue

    path=$(jq -r '.path' <<< "$item_json")
    core_path=$(jq -r '.core_path' <<< "$item_json")

    [[ -z "$path" || -z "$core_path" ]] && continue

    # Deduplicate by path (keep first = most recent)
    if [[ -n "${seen_paths[$path]:-}" ]]; then
      continue
    fi
    seen_paths["$path"]=1

    # Extract system from path (/roms/{system}/...)
    system=""
    if [[ "$path" =~ ^/roms/([^/]+)/ ]]; then
      system="${BASH_REMATCH[1]}"
    else
      echo "[recent-games] WARN: Path outside /roms/{system}/, skipping: $path"
      continue
    fi

    # Map to display prefix; skip unknown systems
    prefix="${SYSTEM_PREFIX[$system]:-}"
    if [[ -z "$prefix" ]]; then
      echo "[recent-games] WARN: Unknown system '$system' for '$path', skipping"
      continue
    fi

    # Strip extension from ROM basename
    rom_basename=$(basename "$path")
    rom_name=$(strip_extensions "$rom_basename")

    # Strip region tags like (USA), (Europe), etc. and trim whitespace
    clean_name=$(echo "$rom_name" | sed -E 's/\s*\([^)]*\)\s*//g' | xargs)

    # Build display name and command
    display_name="${prefix} - ${clean_name}"
    cmd="retroarch -L \"${core_path}\" \"${path}\" --fullscreen --appendconfig /scripts/retroarch-overrides.cfg"

    # Locate scraped media (miximages > covers > screenshots)
    image_path=""
    if [[ -r "${ES_DE_MEDIA_BASE}/${system}/miximages/${rom_name}.png" ]]; then
      image_path="${ES_DE_MEDIA_BASE}/${system}/miximages/${rom_name}.png"
    elif [[ -r "${ES_DE_MEDIA_BASE}/${system}/covers/${rom_name}.png" ]]; then
      image_path="${ES_DE_MEDIA_BASE}/${system}/covers/${rom_name}.png"
    elif [[ -r "${ES_DE_MEDIA_BASE}/${system}/screenshots/${rom_name}.png" ]]; then
      image_path="${ES_DE_MEDIA_BASE}/${system}/screenshots/${rom_name}.png"
    fi

    # Build single app entry via jq (avoid string concatenation)
    entry=$(jq -n \
      --arg name "$display_name" \
      --arg cmd "$cmd" \
      --arg image "$image_path" \
      --argjson index "$entry_index" \
      '{
        name: $name,
        cmd: $cmd,
        "image-path": $image,
        output: "",
        index: $index
      }'
    )

    # Append to entries array
    all_entries=$(jq --argjson e "$entry" '. + [$e]' <<< "$all_entries")
    entry_index=$((entry_index + 1))

    # Cap at 10 games
    if [[ "$entry_index" -gt 10 ]]; then
      break
    fi
  done < <(jq -r '.items[] | {path, core_path} | @json' "$HISTORY_FILE" || true)

  write_apps_json "$all_entries"
  sleep "$POLL_INTERVAL"
done
