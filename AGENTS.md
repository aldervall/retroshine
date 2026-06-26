# RetroShine — AGENTS.md

## Quick Setup (First Run)

```bash
# Build and start for development/testing
docker compose up -d

# Full LXC deployment (with smoke tests)
bash deploy.sh  # Edit for your PVE/LXC details
```

## Core Commands

- `docker logs retro-shine` - View container logs
- `docker exec retro-shine pgrep sunshine` - Check if running
- `bash scripts/smoke-test.sh` - Verify after container start
- `docker compose down && docker compose up -d` - Restart

## Critical Architecture

**Single container with host network, privileged:**
- Intel UHD 630 iGPU renders Xvfb (:99)
- VAAPI H.264 hardware encoding (`adapter_name = /dev/dri/card1`)
- ES-DE + RetroArch with 5 systems (NES, SNES, GB, GBA, Genesis)
- Gamepad passthrough via `/dev/uinput` → `input-watcher.sh` → `/dev/input/js*`

## High-Risk Controller Gotchas

**Controllers not detected?** Common fixes:
1. **input-watcher.sh MUST run** (creates `/dev/input/js*` nodes from virtual gamepads)
2. **ES-DE waits for gamepad nodes** via `launch-es-de.sh` (15s timeout)
3. **Check**: `docker exec retro-shine ls /dev/input/js*`

**Gamepad flow:**
Moonlight client → `/dev/uinput` → Sunshine creates virtual X360 → `input-watcher` creates `/dev/input/jsX` → SDL apps (ES-DE/RetroArch) detect joysticks

### Critical Audio Fix
**ES-DE black screen + "Unable to open audio device"?** SDL defaults to ALSA, but container has no ALSA hardware.
- Set `SDL_AUDIODRIVER=pulse` in Dockerfile and docker-compose.yml environment
- PulseAudio socket at `unix:/tmp/runtime-lizard/pulse/native` (not custom `/tmp/pulse-socket`)

### input-watcher.sh Bug Fix
**Device nodes not created?** The script uses `IFS=':'` for parsing `/sys/devices/.../dev` files because format is `major:minor` without space. Original `read major minor` fails.

### RetroArch fullscreen
RetroArch standalone needs `--fullscreen` flag (`retroarch --menu --fullscreen`). Unlike ES-DE 3.x which dropped `--fullscreen` support, RetroArch still accepts it.

## Ports (Moonlight Protocol)

| Port | Purpose |
|------|---------|
| 47984/tcp | HTTPS pairing/control |
| 47989/tcp | HTTP pairing |
| 47990/tcp | HTTPS Web UI (admin/retro123) |
| 48010/tcp | RTSP stream setup |

## Device Passthrough (Critical)

```yaml
devices:
  - /dev/dri:/dev/dri:rw    # VAAPI encoding (Intel iGPU)
  - /dev/uinput:/dev/uinput  # Controller passthrough
  - /dev/uhid:/dev/uhid      # Controller passthrough
```

## Smoke Tests (Run after any change)

```bash
bash scripts/smoke-test.sh
```

Must pass: container, sunshine, Xvfb, Web UI, encoder, ES-DE, RetroArch, 4+ cores, uinput

## Adding ROMs

```bash
# Live-sync (no restart needed)
cp mygame.sfc /opt/retroshine/roms/snes/

# Or with rebuild
bash scripts/add-roms.sh <system> <rom-file>
```

Systems: nes, snes, gb, gba, genesis (784 SNES ROMs pre-loaded)