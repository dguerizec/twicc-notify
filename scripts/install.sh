#!/usr/bin/env bash
# Install APK on connected device, preserving app data (settings, auth tokens).
# Uses "adb install -r" instead of "flutter install" which uninstalls first.
#
# Usage: ./scripts/install.sh [--wifi]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APK_PATH="$PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"

# Handle --wifi flag
if [[ "${1:-}" == "--wifi" ]]; then
    "$SCRIPT_DIR/wifi-connect.sh"
    echo ""
fi

if [ ! -f "$APK_PATH" ]; then
    echo "Error: APK not found at $APK_PATH"
    echo "Run ./scripts/build.sh first."
    exit 1
fi

# Find connected device
DEVICE=$(adb devices | awk 'NR>1 && /device$/ {print $1; exit}')
if [ -z "$DEVICE" ]; then
    echo "Error: No Android device connected."
    echo "Connect via USB or use --wifi flag."
    exit 1
fi

DEVICE_NAME=$(adb -s "$DEVICE" shell getprop ro.product.model 2>/dev/null || echo "$DEVICE")
echo "Installing on $DEVICE_NAME ($DEVICE)..."
echo "Using replace mode (app data preserved)."

adb -s "$DEVICE" install -r "$APK_PATH"

echo ""
echo "Installed successfully. Settings preserved."
