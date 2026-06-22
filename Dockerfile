FROM lizardbyte/sunshine:v2025.924.154138-ubuntu-24.04

USER root

LABEL description="Sunshine + ES-DE + RetroArch retro gaming streamer"

# Create lizard user if it doesn't exist (preserve existing user if present)
ARG LIZARD_UID=1000
ARG LIZARD_GID=1000
RUN if ! id -u lizard >/dev/null 2>&1; then \
        if getent group lizard >/dev/null 2>&1; then \
            useradd -m -u ${LIZARD_UID} -g ${LIZARD_GID} -s /bin/bash lizard; \
        else \
            groupadd -g ${LIZARD_GID} lizard && \
            useradd -m -u ${LIZARD_UID} -g ${LIZARD_GID} -s /bin/bash lizard; \
        fi; \
    fi

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb xserver-xorg-video-dummy \
    mesa-utils mesa-va-drivers libgl1-mesa-dri libglx-mesa0 intel-media-va-driver \
    pulseaudio pulseaudio-utils \
    libsdl2-2.0-0 libboost-filesystem-dev libboost-system-dev \
    libfreeimage-dev libfreetype6-dev libcurl4-openssl-dev libpugixml-dev rapidjson-dev \
    retroarch libretro-nestopia libretro-gambatte libretro-mgba libretro-genesisplusgx libretro-snes9x \
    curl jq x11-utils ca-certificates file unzip \
    && rm -rf /var/lib/apt/lists/*

# Download and extract ES-DE AppImage (uruntime format extracts to CWD)
RUN curl -L -o /tmp/es-de.AppImage \
    "https://gitlab.com/es-de/emulationstation-de/-/package_files/288156961/download" \
    && chmod +x /tmp/es-de.AppImage \
    && cd /tmp && /tmp/es-de.AppImage --appimage-extract >/dev/null 2>&1 \
    && EXTRACT_DIR=$(ls -d /tmp/AppDir /tmp/squashfs-root 2>/dev/null | head -1) \
    && if [ -z "$EXTRACT_DIR" ] || [ ! -d "$EXTRACT_DIR" ]; then \
          echo "Look at /tmp:"; ls -la /tmp/; \
          echo "Look at /:"; ls -la /; \
          exit 1; \
        fi \
    && mv "$EXTRACT_DIR" /opt/es-de \
    && rm -f /tmp/es-de.AppImage \
    && if [ -f /opt/es-de/AppRun ]; then \
          ln -sf /opt/es-de/AppRun /usr/local/bin/es-de; \
        elif ls /opt/es-de/*.AppImage 2>/dev/null; then \
          ln -sf /opt/es-de/*.AppImage /usr/local/bin/es-de; \
        fi

RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb xserver-xorg-video-dummy \
    mesa-utils mesa-va-drivers libgl1-mesa-dri libglx-mesa0 intel-media-va-driver \
    pulseaudio pulseaudio-utils \
    libsdl2-2.0-0 libboost-filesystem-dev libboost-system-dev \
    libfreeimage-dev libfreetype6-dev libcurl4-openssl-dev libpugixml-dev rapidjson-dev \
    retroarch libretro-nestopia libretro-gambatte libretro-mgba libretro-genesisplusgx libretro-snes9x \
    curl jq x11-utils ca-certificates file unzip \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /home/lizard/.config/sunshine
COPY config/sunshine.conf /home/lizard/.config/sunshine/sunshine.conf
COPY config/apps.json /home/lizard/.config/sunshine/apps.json
COPY es-de/es_systems.cfg /root/.emulationstation/es_systems.cfg
COPY es-de/es_systems.cfg /home/lizard/.emulationstation/es_systems.cfg
COPY scripts/entrypoint.sh /scripts/entrypoint.sh
COPY scripts/add-roms.sh /scripts/add-roms.sh
COPY roms/ /roms/

RUN chmod +x /scripts/entrypoint.sh /scripts/add-roms.sh \
    && ln -sf /roms /home/lizard/ROMs \
    && chown -R lizard:lizard /scripts/entrypoint.sh /scripts/add-roms.sh /home/lizard/.config/sunshine

ENV DISPLAY=:99
ENV XDG_RUNTIME_DIR=/tmp/.X11-unix
ENV PULSE_SERVER=unix:/tmp/pulse-socket
ENV SUNSHINE_USER=admin
ENV SUNSHINE_PASS=retro123

USER root
