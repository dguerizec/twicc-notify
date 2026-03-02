#!/usr/bin/env bash
# Connect to a WiFi-paired Android device.
# Reads connection info from .wifi-device (created by wifi-pair.sh).
# Can override debug port with: ./scripts/wifi-connect.sh [debug_port]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/.wifi-device"
ADB="${ADB:-adb}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: No WiFi device configured."
    echo "Run ./scripts/wifi-pair.sh first to pair your device."
    exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Allow overriding debug port via argument (port can change on device restart)
if [ $# -ge 1 ]; then
    DEBUG_PORT="$1"
fi

if [ -z "${DEVICE_IP:-}" ] || [ -z "${DEBUG_PORT:-}" ]; then
    echo "Error: Invalid .wifi-device config. Run ./scripts/wifi-pair.sh again."
    exit 1
fi

# Check if already connected
if $ADB devices 2>/dev/null | grep -q "$DEVICE_IP:$DEBUG_PORT.*device$"; then
    echo "Already connected to $DEVICE_IP:$DEBUG_PORT"
    exit 0
fi

echo "Connecting to $DEVICE_IP:$DEBUG_PORT..."
$ADB connect "$DEVICE_IP:$DEBUG_PORT"
