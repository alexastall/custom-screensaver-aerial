#!/bin/sh

set -e -o pipefail

MOUNT_TARGET="/usr/palm/applications/com.webos.app.screensaver/qml/main.qml"
QML_PATH="$(dirname "$(realpath "$0")")/screensaver-main.qml"

if [[ ! -f "$MOUNT_TARGET" ]]; then
    echo "[-] Target file does not exist: $MOUNT_TARGET" >&2
    exit 1
fi

if [[ ! -f "$QML_PATH" ]]; then
    echo "[-] Aerial QML missing: $QML_PATH" >&2
    exit 1
fi

# If something else (e.g. older custom-screensaver) is bound, rebind to aerial
if findmnt "$MOUNT_TARGET" >/dev/null 2>&1; then
    CURRENT="$(findmnt -n -o SOURCE --target "$MOUNT_TARGET" 2>/dev/null || true)"
    case "$CURRENT" in
        *custom-screensaver-aerial*)
            echo "[~] Aerial already enabled" >&2
            exit 0
            ;;
        *)
            echo "[*] Replacing existing bind: $CURRENT" >&2
            umount "$MOUNT_TARGET" || true
            ;;
    esac
fi

mount --bind "$QML_PATH" "$MOUNT_TARGET"
echo "[+] Aerial screensaver enabled" >&2
