#!/usr/bin/env bash
# Initialize Flutter project structure.
# Generates platform directories (android/, macos/) for your Flutter SDK version.
# Existing lib/ files are NOT overwritten.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "Initializing Flutter project structure..."
flutter create --project-name twicc_notify --org net.guerizec .

echo ""
echo "Installing dependencies..."
flutter pub get

echo ""
echo "Done. Now apply platform configurations:"
echo "  Android: merge permissions from android/app/src/main/AndroidManifest.xml"
echo "  macOS:   merge entitlements from macos/Runner/*.entitlements"
