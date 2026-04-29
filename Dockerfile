# ==============================================================
# LLM Wiki — Docker image
# Runs the Tauri desktop app in a container with noVNC access
# ==============================================================

# -------------------- Stage 1: Build --------------------
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# System build dependencies for Tauri on Linux
RUN apt-get update && apt-get install -y \
    curl wget gnupg2 build-essential pkg-config \
    libwebkit2gtk-4.1-dev \
    libappindicator3-dev \
    librsvg2-dev \
    patchelf \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

# Cache npm dependencies
COPY package.json package-lock.json ./
RUN npm ci

# Copy source code
COPY . .

# Build the Tauri application (binary only, skip .deb/.rpm/AppImage bundling)
RUN npm run tauri build -- --no-bundle

# -------------------- Stage 2: Runtime --------------------
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Runtime libraries required by Tauri / webkit2gtk on Linux
RUN apt-get update && apt-get install -y \
    libwebkit2gtk-4.1-0 \
    libgtk-3-0 \
    libappindicator3-1 \
    librsvg2-2 \
    libgdk-pixbuf2.0-0 \
    libcairo2 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libglib2.0-0 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libsoup-3.0-0 \
    libjavascriptcoregtk-4.1-0 \
    libdbus-glib-1-2 \
    fonts-liberation \
    fonts-noto-color-emoji \
    fonts-noto-cjk \
    # CJK fonts support
    locales \
    dbus-x11 \
    # Chinese input method (fcitx5 with F12 trigger — avoids browser key conflicts)
    fcitx5 \
    fcitx5-chinese-addons \
    fcitx5-frontend-gtk3 \
    im-config \
    # Display server & remote access
    xvfb \
    x11vnc \
    novnc \
    websockify \
    openbox \
    # Keyboard support for VNC
    x11-xkb-utils \
    xkb-data \
    # Clipboard tools for UTF-8 sync between noVNC and X11
    xclip \
    autocutsel \
    # Utilities
    dbus \
    && rm -rf /var/lib/apt/lists/*

# Generate locales
RUN locale-gen en_US.UTF-8 zh_CN.UTF-8

# Remove fcitx5 GTK3 immodule so GTK apps never auto-load it (prevents keyboard conflicts)
# fcitx5 is started manually in entrypoint.sh instead
RUN rm -f /usr/lib/x86_64-linux-gnu/gtk-3.0/3.0.0/immodules/im-fcitx5.so \
    && gtk-query-immodules-3.0 --update-cache 2>/dev/null || true

# Pre-create fcitx5 config with F12 trigger key (avoids browser Ctrl+Shift interception)
RUN mkdir -p /etc/skel/.config/fcitx5

# fcitx5 profile: defines input method groups and hotkey
RUN printf '[Groups/0]\nName=Default\nDefault Layout=us\nDefaultIM=pinyin\n\n[Groups/0/Items/0]\nName=keyboard-us\nLayout=\n\n[Groups/0/Items/1]\nName=pinyin\nLayout=\n\n[GroupOrder]\n0=Default\n\n[Hotkey]\nTrigger=F12\nEnumerateForwardKeys=\nEnumerateBackwardKeys=\n' > /etc/skel/.config/fcitx5/profile

# fcitx5 global config
RUN printf '[Hotkey]\nTriggerKey=F12\nEnumerateForwardKeys=\nEnumerateBackwardKeys=\nActivateKey=\nDeactivateKey=\n\n[Hotkey/EnumerateForwardKeys]\n0=\n\n[Hotkey/EnumerateBackwardKeys]\n0=\n' > /etc/skel/.config/fcitx5/config

# fcitx5 pinyin config (ensure cloud pinyin is off for offline use)
RUN mkdir -p /etc/skel/.config/fcitx5/conf \
    && printf '[Hotkey]\n[Behavior]\nCloudPinyinEnabled=False\n' > /etc/skel/.config/fcitx5/conf/pinyin.conf

# Create non-root user and X11 socket directory
RUN useradd -m -s /bin/bash appuser \
    && mkdir -p /tmp/.X11-unix \
    && chmod 1777 /tmp/.X11-unix \
    && mkdir -p /home/appuser/import \
    && chown -R appuser:appuser /home/appuser/import

WORKDIR /opt/llm-wiki

# Copy the built binary
COPY --from=builder /app/src-tauri/target/release/llm-wiki /opt/llm-wiki/llm-wiki

# Copy pdfium shared library (placed next to binary for discovery)
COPY --from=builder /app/src-tauri/pdfium/libpdfium.so /opt/llm-wiki/libpdfium.so

# Copy entrypoint script
COPY docker/entrypoint.sh /opt/llm-wiki/entrypoint.sh
RUN chmod +x /opt/llm-wiki/entrypoint.sh

# Create data directory for wiki projects
RUN mkdir -p /home/appuser/wiki && chown -R appuser:appuser /home/appuser/wiki
VOLUME /home/appuser/wiki

# Create import directory for uploading files from host
RUN mkdir -p /home/appuser/import && chown -R appuser:appuser /home/appuser/import
VOLUME /home/appuser/import

# noVNC web port
EXPOSE 6080

# Environment
ENV DISPLAY=:0
ENV RESOURCES_DIR=/opt/llm-wiki
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en
ENV LC_ALL=en_US.UTF-8

USER appuser

ENTRYPOINT ["/opt/llm-wiki/entrypoint.sh"]
