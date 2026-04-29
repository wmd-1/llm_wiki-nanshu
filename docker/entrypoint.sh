#!/bin/bash
set -e

# ============================================================
# LLM Wiki — Docker entrypoint
# Starts Xvfb + openbox + x11vnc + noVNC, then launches the app
# ============================================================

DISPLAY_NUM=0
SCREEN_SIZE="${SCREEN_SIZE:-1280x800x24}"
VNC_PORT=5900
NOVNC_PORT=6080

cleanup() {
    echo "[entrypoint] Shutting down..."
    kill $(jobs -p) 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM

# ---------- 1. Xvfb (virtual display) ----------
echo "[entrypoint] Starting Xvfb on :${DISPLAY_NUM} (${SCREEN_SIZE})"
Xvfb :${DISPLAY_NUM} -screen 0 ${SCREEN_SIZE} -ac +extension GLX +render -noreset &
XVFB_PID=$!
sleep 1

# Verify Xvfb is running
if ! kill -0 ${XVFB_PID} 2>/dev/null; then
    echo "[entrypoint] ERROR: Xvfb failed to start"
    exit 1
fi

export DISPLAY=:${DISPLAY_NUM}

# Set XDG runtime directory (required by fcitx5 and other components)
export XDG_RUNTIME_DIR="/tmp/runtime-appuser"
mkdir -p "${XDG_RUNTIME_DIR}" 2>/dev/null || true
chmod 0700 "${XDG_RUNTIME_DIR}" 2>/dev/null || true

# ---------- 2. Window manager ----------
echo "[entrypoint] Starting openbox window manager"
openbox &
sleep 0.5

# Set base keyboard layout (must be before fcitx5 starts)
setxkbmap us 2>/dev/null || true

# Ensure dbus session is running and its address is exported (fcitx5 requires it)
if [ -z "${DBUS_SESSION_BUS_ADDRESS}" ]; then
    echo "[entrypoint] Starting dbus daemon"
    eval $(dbus-launch --sh-syntax) 2>/dev/null || true
    sleep 1
    # Verify dbus is accessible
    if [ -n "${DBUS_SESSION_BUS_ADDRESS}" ]; then
        echo "[entrypoint] dbus started at ${DBUS_SESSION_BUS_ADDRESS}"
    else
        echo "[entrypoint] WARNING: dbus-launch failed, trying dbus-daemon"
        dbus-daemon --session --fork 2>/dev/null || true
        sleep 0.5
    fi
fi

# Generate fcitx5 config at runtime (no image rebuild needed)
mkdir -p "${HOME}/.config/fcitx5/conf"

# profile: input method group + trigger key
# DefaultIM=pinyin means Chinese input is active by default
cat > "${HOME}/.config/fcitx5/profile" << 'EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=pinyin

[Groups/0/Items/0]
Name=pinyin
Layout=

[Groups/0/Items/1]
Name=keyboard-us
Layout=

[GroupOrder]
0=Default

[Hotkey]
Trigger=Control_semicolon
EnumerateForwardKeys=
EnumerateBackwardKeys=
EOF

# global config: hotkey definition
cat > "${HOME}/.config/fcitx5/config" << 'EOF'
[Hotkey]
TriggerKey=Control_semicolon
EnumerateForwardKeys=
EnumerateBackwardKeys=
ActivateKey=
DeactivateKey=
EOF

# pinyin config: disable cloud pinyin (offline server)
cat > "${HOME}/.config/fcitx5/conf/pinyin.conf" << 'EOF'
[Hotkey]
[Behavior]
CloudPinyinEnabled=False
EOF

# Clean stale fcitx5 entry from GTK immodules cache (im-fcitx5.so was removed from image)
# If not cleaned, GTK tries to load the missing .so and fails, breaking all IM input
GTK_IM_CACHE="/usr/lib/x86_64-linux-gnu/gtk-3.0/3.0.0/immodules.cache"
if [ -f "${GTK_IM_CACHE}" ] && grep -q fcitx5 "${GTK_IM_CACHE}" 2>/dev/null; then
    echo "[entrypoint] Cleaning fcitx5 entry from GTK immodules cache"
    sed -i '/fcitx5/d' "${GTK_IM_CACHE}" 2>/dev/null || true
fi

# Start fcitx5 (Ctrl+; to toggle Chinese/English input)
echo "[entrypoint] Starting fcitx5 (Ctrl+; = toggle input, default: Chinese Pinyin)"
fcitx5 -d --replace 2>&1 &
sleep 2

# Activate pinyin by default via dbus
if pgrep -x fcitx5 > /dev/null 2>&1; then
    # Extract dbus session address from dbus-launch saved file
    DBUS_SESSION_FILE=$(find /home/appuser/.dbus/session-bus -type f 2>/dev/null | head -1)
    if [ -f "${DBUS_SESSION_FILE}" ]; then
        DBUS_ADDR=$(grep '^DBUS_SESSION_BUS_ADDRESS=' "${DBUS_SESSION_FILE}" 2>/dev/null | head -1 | cut -d"'" -f2)
    fi
    # Activate fcitx5 and switch to pinyin after a delay (need app window focused)
    if [ -n "${DBUS_ADDR}" ]; then
        (sleep 5 && DBUS_SESSION_BUS_ADDRESS="${DBUS_ADDR}" DISPLAY=:0 fcitx5-remote -s pinyin 2>/dev/null && DBUS_SESSION_BUS_ADDRESS="${DBUS_ADDR}" DISPLAY=:0 fcitx5-remote -o 2>/dev/null) &
        echo "[entrypoint] fcitx5 default input set to Pinyin via dbus"
    fi
    FCITX5_PID=$(pgrep -x fcitx5 | head -1)
    echo "[entrypoint] fcitx5 started (PID: ${FCITX5_PID}), default: Pinyin (Chinese)"
else
    echo "[entrypoint] WARNING: fcitx5 failed to start, Chinese input may not work"
fi

# Use XIM protocol to connect to fcitx5 (not GTK_IM_MODULE=fcitx which requires im-fcitx5.so)
# XMODIFIERS=@im=fcitx tells GTK to use XIM to talk to fcitx5
export GTK_IM_MODULE=xim
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx

# ---------- 3. VNC server ----------
echo "[entrypoint] Starting x11vnc on port ${VNC_PORT}"
x11vnc -display :${DISPLAY_NUM} \
    -forever \
    -nopw \
    -listen 0.0.0.0 \
    -rfbport ${VNC_PORT} \
    -shared \
    -noxdamage \
    -cursor arrow \
    -xkb \
    -capslock \
    -clear_mods \
    -norepeat \
    &
sleep 1

# ---------- 4. noVNC / websockify ----------
# Sync X11 clipboards (PRIMARY & CLIPBOARD) to fix UTF-8 paste issues
if command -v autocutsel > /dev/null 2>&1; then
    autocutsel -fork && autocutsel -selection CLIPBOARD -fork
    echo "[entrypoint] autocutsel started for clipboard sync"
fi

# Find noVNC web directory
NOVNC_WEB_DIR="/usr/share/novnc"
if [ ! -d "${NOVNC_WEB_DIR}" ]; then
    NOVNC_WEB_DIR="/usr/share/novnc/web"
fi

echo "[entrypoint] Starting websockify (noVNC) on port ${NOVNC_PORT}"
websockify --web ${NOVNC_WEB_DIR} ${NOVNC_PORT} localhost:${VNC_PORT} &
sleep 1

# ---------- 5. Launch the app ----------
echo "[entrypoint] Starting LLM Wiki"
echo "[entrypoint] Access the app at:"
echo "  - Standard:  http://localhost:${NOVNC_PORT}/vnc.html"
echo "  - HiDPI:     http://localhost:${NOVNC_PORT}/vnc.html?quality=9&resize=scale&autoconnect=true"
echo "[entrypoint] Wiki data volume: /home/appuser/wiki"
echo "[entrypoint] Import volume: /home/appuser/import  (mount host files here)"
echo "[entrypoint] -----------------------------------------------"
echo "[entrypoint] Chinese input: Ctrl+; to toggle Pinyin/English (default: Pinyin)"
echo "[entrypoint] -----------------------------------------------"

cd /opt/llm-wiki
exec ./llm-wiki
