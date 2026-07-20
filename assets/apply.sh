#!/bin/sh

set -e -o pipefail

ASSETS="$(dirname "$(realpath "$0")")"
AERIAL_QML="$ASSETS/screensaver-main.qml"
AERIAL_TARGET="/usr/palm/applications/com.webos.app.screensaver/qml/main.qml"

# Suppress Live TV / HDMI stock "Not Programmed" / no-signal photo screensaver
# which otherwise overrides the system aerial screensaver.
INPUT_CREATOR_QML="$ASSETS/inputcommon-ScreensaverCreator.qml"
INPUT_CREATOR_TARGET="/usr/palm/applications/com.webos.app.inputcommon/qml/InvisibleComponent/ScreensaverCreator.qml"

bind_file() {
    local src="$1"
    local dst="$2"
    local label="$3"

    if [[ ! -f "$src" ]]; then
        echo "[-] Missing $label source: $src" >&2
        return 1
    fi
    if [[ ! -f "$dst" ]]; then
        echo "[-] Missing $label target: $dst" >&2
        return 1
    fi

    if findmnt "$dst" >/dev/null 2>&1; then
        CURRENT="$(findmnt -n -o SOURCE --target "$dst" 2>/dev/null || true)"
        # Always remount: in-place file replaces leave a //deleted bind.
        echo "[*] Rebinding $label (was: $CURRENT)" >&2
        umount "$dst" || true
    fi

    mount --bind "$src" "$dst"
    echo "[+] $label enabled" >&2
}

bind_file "$AERIAL_QML" "$AERIAL_TARGET" "Aerial QML"
bind_file "$INPUT_CREATOR_QML" "$INPUT_CREATOR_TARGET" "inputcommon ScreensaverCreator"

# Prefer Home as last input so idle/power paths do not open Live TV first.
# Best-effort; ignore failures on older settingsservice builds.
luna-send -n 1 -f luna://com.webos.settingsservice/setSystemSettings \
  '{"category":"general","settings":{"lastInputApp":"com.webos.app.home","physicalLastInputApp":"com.webos.app.home"}}' \
  >/dev/null 2>&1 || true

echo "[+] Aerial apply complete" >&2
