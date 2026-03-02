#!/usr/bin/env bash
# Build + fresh install (wipes app data). Use when you need a clean slate.
#
# Usage: ./scripts/clean-install.sh [--wifi]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

"$SCRIPT_DIR/build.sh"

# Handle --wifi flag
if [[ "${1:-}" == "--wifi" ]]; then
    "$SCRIPT_DIR/wifi-connect.sh"
    echo ""
fi

# Find connected device
DEVICE=$(adb devices | awk 'NR>1 && /device$/ {print $1; exit}')
if [ -z "$DEVICE" ]; then
    echo "Error: No Android device connected."
    echo "Connect via USB or use --wifi flag."
    exit 1
fi

DEVICE_NAME=$(adb -s "$DEVICE" shell getprop ro.product.model 2>/dev/null || echo "$DEVICE")
echo ""
echo "Clean installing on $DEVICE_NAME ($DEVICE)..."
echo "WARNING: This will wipe all app data (settings, auth tokens)."

cd "$PROJECT_DIR"
flutter install -d "$DEVICE"

echo ""
echo "Clean install complete. You will need to reconfigure the app."
